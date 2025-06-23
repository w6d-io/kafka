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

package v1alpha1

import (
	"context"
	"k8s.io/apimachinery/pkg/runtime"
	ctrl "sigs.k8s.io/controller-runtime"
	logf "sigs.k8s.io/controller-runtime/pkg/log"
	"sigs.k8s.io/controller-runtime/pkg/webhook"
	"sigs.k8s.io/controller-runtime/pkg/webhook/admission"
)

// log is for logging in this package.
var kafkatopiclog = logf.Log.WithName("kafkatopic-resource")

// SetupWebhookWithManager will setup the manager to manage the webhooks
func (r *KafkaTopic) SetupWebhookWithManager(mgr ctrl.Manager) error {
	return ctrl.NewWebhookManagedBy(mgr).
		For(r).
		Complete()
}

// TODO(user): EDIT THIS FILE!  THIS IS SCAFFOLDING FOR YOU TO OWN!

// +kubebuilder:webhook:path=/mutate-kafka-w6d-io-v1alpha1-kafkatopic,mutating=true,failurePolicy=fail,sideEffects=None,groups=kafka.w6d.io,resources=kafkatopics,verbs=create;update,versions=v1alpha1,name=mkafkatopic.kb.io,admissionReviewVersions=v1

var _ webhook.CustomDefaulter = &KafkaTopic{}

// Default implements webhook.Defaulter so a webhook will be registered for the type
func (r *KafkaTopic) Default(_ context.Context, _ runtime.Object) error {
	kafkatopiclog.Info("default", "name", r.Name)

	// TODO(user): fill in your defaulting logic.

	return nil
}

// TODO(user): change verbs to "verbs=create;update;delete" if you want to enable deletion validation.
// NOTE: The 'path' attribute must follow a specific pattern and should not be modified directly here.
// Modifying the path for an invalid path can cause API server errors; failing to locate the webhook.
// +kubebuilder:webhook:path=/validate-kafka-w6d-io-v1alpha1-kafkatopic,mutating=false,failurePolicy=fail,sideEffects=None,groups=kafka.w6d.io,resources=kafkatopics,verbs=create;update,versions=v1alpha1,name=vkafkatopic.kb.io,admissionReviewVersions=v1

var _ webhook.CustomValidator = &KafkaTopic{}

// ValidateCreate implements webhook.Validator so a webhook will be registered for the type
func (r *KafkaTopic) ValidateCreate(ctx context.Context, obj runtime.Object) (admission.Warnings, error) {
	kafkatopiclog.Info("validate create", "name", r.Name)

	// TODO(user): fill in your validation logic upon object creation.
	return nil, nil
}

// ValidateUpdate implements webhook.Validator so a webhook will be registered for the type
func (r *KafkaTopic) ValidateUpdate(ctx context.Context, oldObj runtime.Object, newObj runtime.Object) (admission.Warnings, error) {
	kafkatopiclog.Info("validate update", "name", r.Name)

	// TODO(user): fill in your validation logic upon object update.
	return nil, nil
}

// ValidateDelete implements webhook.Validator so a webhook will be registered for the type
func (r *KafkaTopic) ValidateDelete(ctx context.Context, obj runtime.Object) (admission.Warnings, error) {
	kafkatopiclog.Info("validate delete", "name", r.Name)

	// TODO(user): fill in your validation logic upon object deletion.
	return nil, nil
}
