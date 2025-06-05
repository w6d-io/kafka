/*
Copyright 2025 WILDCARD.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package controller

import (
	"context"
	"fmt"
	"net"
	"strconv"
	"time"

	"github.com/google/uuid"
	kafka "github.com/segmentio/kafka-go"
	"k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/api/meta"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/util/retry"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller"

	kafkav1alpha1 "github.com/w6d-io/kafka/api/v1alpha1"
	"github.com/w6d-io/kafka/internal/pkg/k"
	"github.com/w6d-io/x/logx"
)

// KafkaTopicReconciler reconciles a KafkaTopic object
type KafkaTopicReconciler struct {
	client.Client
	Scheme *runtime.Scheme
}

// +kubebuilder:rbac:groups=kafka.kafka.w6d.io,resources=kafkatopics,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=kafka.kafka.w6d.io,resources=kafkatopics/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=kafka.kafka.w6d.io,resources=kafkatopics/finalizers,verbs=update

// Reconcile is part of the main kubernetes reconciliation loop which aims to
// move the current state of the cluster closer to the desired state.
// TODO(user): Modify the Reconcile function to compare the state specified by
// the KafkaTopic object against the actual cluster state, and then
// perform operations to make the cluster state reflect the state specified by
// the user.
//
// For more details, check Reconcile and its Result here:
// - https://pkg.go.dev/sigs.k8s.io/controller-runtime@v0.19.0/pkg/reconcile
func (r *KafkaTopicReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	correlationID := uuid.New().String()

	ctx = context.WithValue(ctx, logx.CorrelationID, correlationID)
	ctx = context.WithValue(ctx, logx.Kind, "KafkaTopic")

	log := logx.WithName(ctx, "reconcile")

	var kafkaTopic kafkav1alpha1.KafkaTopic
	if err := r.Get(ctx, req.NamespacedName, &kafkaTopic); err != nil {
		if errors.IsNotFound(err) {
			// Request object not found, could have been deleted after reconcile request.
			log.Info("KafkaTopic resource not found. Ignoring since object must be deleted")
			return ctrl.Result{}, nil
		}
		// Error reading the object - requeue the request.
		log.Error(err, "Failed to get KafkaTopic")
		return ctrl.Result{}, err
	}
	// Check if bootstrap server is specified
	if kafkaTopic.Spec.BoostrapServer == nil || *kafkaTopic.Spec.BoostrapServer == "" {
		log.Error(fmt.Errorf("bootstrap server not specified"), "Bootstrap server is required")
		if err := r.UpdateStatus(ctx, req.NamespacedName, kafkav1alpha1.KafkaTopicStatus{
			State: kafkav1alpha1.Failed,
			Message: fmt.Sprintf(
				"Bootstrap server is required, please specify it in the KafkaTopic %s/%s",
				kafkaTopic.Namespace,
				kafkaTopic.Name,
			),
		}); err != nil {
			log.Error(err, "Failed to update status")
			return ctrl.Result{RequeueAfter: time.Minute * 5}, err
		}
		return ctrl.Result{RequeueAfter: time.Minute * 5}, nil
	}

	// Check if topics are specified
	if kafkaTopic.Spec.Topics == nil || len(*kafkaTopic.Spec.Topics) == 0 {
		log.Info("No topics specified, nothing to create")
		return ctrl.Result{}, nil
	}

	// Create Kafka connection
	conn, err := k.CreateKafkaConnection(ctx, *kafkaTopic.Spec.BoostrapServer)
	if err != nil {
		log.Error(err, "Failed to create Kafka connection")
		if err := r.UpdateStatus(ctx, req.NamespacedName, kafkav1alpha1.KafkaTopicStatus{
			State: kafkav1alpha1.Failed,
			Message: fmt.Sprintf(
				"Failed to create Kafka connection, please check bootstrap server %s/%s",
				kafkaTopic.Namespace,
				kafkaTopic.Name,
			),
		}); err != nil {
			log.Error(err, "Failed to update status")
			return ctrl.Result{RequeueAfter: time.Minute * 2}, err
		}
		return ctrl.Result{RequeueAfter: time.Minute * 2}, err
	}
	defer func(conn *kafka.Conn) {
		err := conn.Close()
		if err != nil {
			log.Error(err, "connection close failed")
		}
	}(conn)

	// Get existing topics to avoid recreation
	partitions, err := conn.ReadPartitions()
	if err != nil {
		log.Error(err, "Failed to read existing partitions")
		if err := r.UpdateStatus(ctx, req.NamespacedName, kafkav1alpha1.KafkaTopicStatus{
			State: kafkav1alpha1.Failed,
			Message: fmt.Sprintf(
				"Failed to read existing partitions, please check bootstrap server %s/%s",
				kafkaTopic.Namespace,
				kafkaTopic.Name,
			),
		}); err != nil {
			log.Error(err, "Failed to read existing partitions")
		}
		return ctrl.Result{RequeueAfter: time.Minute * 2}, err
	}

	// Create a set of existing topics
	existingTopics := make(map[string]bool)
	for _, partition := range partitions {
		existingTopics[partition.Topic] = true
	}

	// Prepare topics to create
	var topicsToCreate []kafka.TopicConfig
	for _, topic := range *kafkaTopic.Spec.Topics {
		if !existingTopics[topic.Topic] {
			topicConfig := kafka.TopicConfig{
				Topic: topic.Topic,

				NumPartitions:     int(topic.Partition),
				ReplicationFactor: int(topic.Replica),
				ConfigEntries:     []kafka.ConfigEntry{
					// Add default configurations if needed
					// {ConfigName: "cleanup.policy", ConfigValue: "delete"},
					// {ConfigName: "retention.ms", ConfigValue: "604800000"}, // 7 days
				},
			}
			topicsToCreate = append(topicsToCreate, topicConfig)
			log.Info("Preparing to create topic", "topic", topic.Topic, "partitions", topic.Partition, "replicas", topic.Replica)
		} else {
			log.Info("Topic already exists, skipping", "topic", topic.Topic)
		}
	}

	// Create the topics if any need to be created
	if len(topicsToCreate) > 0 {
		err = conn.CreateTopics(topicsToCreate...)
		if err != nil {
			log.Error(err, "Failed to create topics")
			if err := r.UpdateStatus(ctx, req.NamespacedName, kafkav1alpha1.KafkaTopicStatus{
				State: kafkav1alpha1.Failed,
				Message: fmt.Sprintf(
					"Failed to create topics, please check bootstrap server %s/%s",
					kafkaTopic.Namespace,
					kafkaTopic.Name,
				),
			}); err != nil {
				log.Error(err, "Failed to create topics")
			}
			return ctrl.Result{RequeueAfter: time.Minute * 2}, err
		}

		log.Info("Successfully created topics", "count", len(topicsToCreate))
	}

	// Verify topics were created successfully
	if len(topicsToCreate) > 0 {
		if err := k.VerifyTopicsCreated(ctx, conn, topicsToCreate); err != nil {
			log.Error(err, "Failed to verify topic creation")
			if err := r.UpdateStatus(ctx, req.NamespacedName, kafkav1alpha1.KafkaTopicStatus{
				State: kafkav1alpha1.Failed,
				Message: fmt.Sprintf(
					"Failed to verify topic creation, please check bootstrap server %s/%s",
					kafkaTopic.Namespace,
					kafkaTopic.Name,
				),
			}); err != nil {
				log.Error(err, "Failed to verify topic creation")
			}
			return ctrl.Result{RequeueAfter: time.Minute * 1}, err
		}
	}

	// Update status to reflect current state
	kafkaTopic.Status = kafkav1alpha1.KafkaTopicStatus{
		// Add status fields as needed - you might want to add:
		// CreatedTopics: []string{...},
		// LastReconciled: metav1.Now(),
		// Status: "Ready",
	}

	if err := r.Status().Update(ctx, &kafkaTopic); err != nil {
		log.Error(err, "Failed to update KafkaTopic status")
		return ctrl.Result{}, err
	}

	return ctrl.Result{}, nil
}

func (r *KafkaTopicReconciler) createKafkaConnection(ctx context.Context, bootstrapServer string) (*kafka.Conn, error) {
	// Parse the bootstrap server to get host and port
	host, port, err := net.SplitHostPort(bootstrapServer)
	if err != nil {
		// If no port specified, assume default Kafka port
		host = bootstrapServer
		port = "9092"
	}

	// Convert port to int
	portInt, err := strconv.Atoi(port)
	if err != nil {
		return nil, fmt.Errorf("invalid port: %w", err)
	}

	// Create connection with timeout
	dialer := &kafka.Dialer{
		Timeout:   10 * time.Second,
		DualStack: true,
		// Configure TLS if needed
		// TLS: &tls.Config{},
		// Configure SASL if needed
		// SASLMechanism: plain.Mechanism{
		//     Username: "username",
		//     Password: "password",
		// },
	}

	conn, err := dialer.DialContext(ctx, "tcp", net.JoinHostPort(host, strconv.Itoa(portInt)))
	if err != nil {
		return nil, fmt.Errorf("failed to dial kafka: %w", err)
	}

	return conn, nil
}

func (r *KafkaTopicReconciler) GetStatus(state kafkav1alpha1.State) metav1.ConditionStatus {
	switch state {
	case kafkav1alpha1.Failed:
		return metav1.ConditionFalse
	case kafkav1alpha1.Succeeded:
		return metav1.ConditionTrue
	default:
		return metav1.ConditionUnknown
	}
}

func (r *KafkaTopicReconciler) UpdateStatus(ctx context.Context, nn types.NamespacedName, status kafkav1alpha1.KafkaTopicStatus) error {
	log := logx.WithName(ctx, "KafkaTopicReconciler.UpdateStatus").WithValues("resource", nn, "status", status)
	log.V(1).Info("update status")
	err := retry.RetryOnConflict(retry.DefaultRetry, func() error {
		e := &kafkav1alpha1.KafkaTopic{}
		if err := r.Get(ctx, nn, e); err != nil {
			return err
		}
		e.Status.State = status.State
		e.Status.Message = status.Message
		meta.SetStatusCondition(&e.Status.Conditions, metav1.Condition{
			Type:    string(status.State),
			Status:  r.GetStatus(status.State),
			Reason:  string(status.State),
			Message: status.Message,
		})
		if err := r.Status().Update(ctx, e); err != nil {
			log.Error(err, "update status failed")
		}
		return nil
	})
	return err
}

// SetupWithManager sets up the controller with the Manager.
func (r *KafkaTopicReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&kafkav1alpha1.KafkaTopic{}).
		WithOptions(controller.Options{
			MaxConcurrentReconciles: 10,
		}).
		Complete(r)
}
