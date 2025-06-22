/*
Copyright 2020 WILDCARD SA.

Licensed under the WILDCARD SA License, Version 1.0 (the "License");
WILDCARD SA is register in french corporation.
You may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.w6d.io/licenses/LICENSE-1.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is prohibited.
Created on 01/06/2025
*/

package k

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/twmb/franz-go/pkg/kadm"
	"github.com/twmb/franz-go/pkg/kgo"

	"github.com/w6d-io/kafka/internal/types"
	"github.com/w6d-io/x/logx"
)

func CreateKafkaConnection(ctx context.Context, bootstrapServer string) (*kgo.Client, error) {

	log := logx.WithName(ctx, "CreateKafkaConnection")
	log.Info("Create Kafka connection", "bootstrapServer", bootstrapServer)
	var opts []kgo.Opt
	opts = append(opts,
		kgo.SeedBrokers(strings.Split(bootstrapServer, ",")...),
	)

	client, err := kgo.NewClient(opts...)

	if err != nil {
		return nil, fmt.Errorf("unable to create kafka client: %s", err.Error())
	}

	if err = client.Ping(context.Background()); err != nil {
		return nil, fmt.Errorf("unable to ping cluster: %s", err.Error())
	}
	return client, nil
}

// VerifyTopicsCreated verifies that the topics were successfully created
func VerifyTopicsCreated(ctx context.Context, admin *kadm.Client, createdTopics []types.Topic) error {
	log := logx.WithName(ctx, "VerifyTopicsCreated")
	// Wait a bit for topics to be created
	time.Sleep(2 * time.Second)

	topicDetails, err := admin.ListTopics(ctx)
	if err != nil {
		log.Error(err, "Unable to list topics")
		return err
	}

	// Check if all created topics exist
	for _, topic := range createdTopics {
		if !topicDetails.Has(topic.Topic) {
			return fmt.Errorf("topic %s was not created successfully", topic.Topic)
		}
	}

	return nil
}

func CreateTopics(ctx context.Context, admin *kadm.Client, topics ...types.Topic) error {
	log := logx.WithName(ctx, "createTopic")
	topicDetails, err := admin.ListTopics(ctx)
	if err != nil {
		log.Error(err, "Unable to list topics")
		return err
	}
	var e []error
	for _, topic := range topics {
		if !topicDetails.Has(topic.Topic) {
			resp, _ := admin.CreateTopics(ctx, topic.Partition, topic.Replica, nil, topic.Topic)
			for _, ctr := range resp {
				if ctr.Err != nil {
					log.Error(ctr.Err, "Unable to create topic", "topic", ctr.Topic)
					e = append(e, fmt.Errorf("unable to create topic %s", ctr.Err.Error()))
					continue
				} else {
					log.Info("Topic created", "topic", ctr.Topic)
				}
			}
		} else {
			log.Info("Topic already exists", "topic", topic)
		}
	}
	if len(e) > 0 {
		return errors.Join(e...)
	}
	return nil
}
