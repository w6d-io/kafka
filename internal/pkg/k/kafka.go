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
	"fmt"
	"net"
	"strconv"
	"time"

	"github.com/segmentio/kafka-go"
)

func CreateKafkaConnection(ctx context.Context, bootstrapServer string) (*kafka.Conn, error) {
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

// VerifyTopicsCreated verifies that the topics were successfully created
func VerifyTopicsCreated(_ context.Context, conn *kafka.Conn, createdTopics []kafka.TopicConfig) error {
	// Wait a bit for topics to be created
	time.Sleep(2 * time.Second)

	// Re-read partitions to verify creation
	partitions, err := conn.ReadPartitions()
	if err != nil {
		return fmt.Errorf("failed to read partitions for verification: %w", err)
	}

	// Create a map of existing topics
	existingTopics := make(map[string]bool)
	for _, partition := range partitions {
		existingTopics[partition.Topic] = true
	}

	// Check if all created topics exist
	for _, topic := range createdTopics {
		if !existingTopics[topic.Topic] {
			return fmt.Errorf("topic %s was not created successfully", topic.Topic)
		}
	}

	return nil
}
