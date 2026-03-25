package sqsconsumer

import (
	"context"
	"encoding/json"
	"fmt"
	"log"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/sqs"
	"github.com/aws/aws-sdk-go-v2/service/sqs/types"
)

// HandlerFunc processes a single decoded SQS message body.
type HandlerFunc func(ctx context.Context, body string) error

// Config holds tuning parameters for a Consumer.
type Config struct {
	QueueURL        string
	MaxMessages     int32
	WaitTimeSeconds int32
}

// Consumer polls an SQS queue and dispatches messages to a HandlerFunc.
type Consumer struct {
	client      *sqs.Client
	queueURL    string
	handler     HandlerFunc
	maxMessages int32
	waitTime    int32
}

// New creates a Consumer. cfg.QueueURL and handler are required.
func New(client *sqs.Client, cfg Config, handler HandlerFunc) *Consumer {
	if cfg.MaxMessages == 0 {
		cfg.MaxMessages = 10
	}
	if cfg.WaitTimeSeconds == 0 {
		cfg.WaitTimeSeconds = 20
	}
	return &Consumer{
		client:      client,
		queueURL:    cfg.QueueURL,
		handler:     handler,
		maxMessages: cfg.MaxMessages,
		waitTime:    cfg.WaitTimeSeconds,
	}
}

// Start polls the queue in a loop until ctx is cancelled.
func (c *Consumer) Start(ctx context.Context) error {
	log.Printf("sqsconsumer: starting on %s", c.queueURL)
	for {
		select {
		case <-ctx.Done():
			log.Println("sqsconsumer: context cancelled, stopping")
			return nil
		default:
			if err := c.poll(ctx); err != nil {
				log.Printf("sqsconsumer: poll error: %v", err)
			}
		}
	}
}

// poll performs one ReceiveMessage call and processes all returned messages.
func (c *Consumer) poll(ctx context.Context) error {
	out, err := c.client.ReceiveMessage(ctx, &sqs.ReceiveMessageInput{
		QueueUrl:              aws.String(c.queueURL),
		MaxNumberOfMessages:   c.maxMessages,
		WaitTimeSeconds:       c.waitTime,
		AttributeNames:        []types.QueueAttributeName{"All"},
		MessageAttributeNames: []string{"All"},
	})
	if err != nil {
		return fmt.Errorf("ReceiveMessage: %w", err)
	}

	for _, msg := range out.Messages {
		c.process(ctx, msg)
	}
	return nil
}

// process handles a single message: unwrap → dispatch → delete or leave.
func (c *Consumer) process(ctx context.Context, msg types.Message) {
	body := aws.ToString(msg.Body)

	// SNS wraps the real payload in an envelope when delivering to SQS.
	if unwrapped, err := unwrapSNS(body); err == nil {
		body = unwrapped
	}

	if err := c.handler(ctx, body); err != nil {
		log.Printf("sqsconsumer: handler error (msg %s): %v — message will return to queue",
			aws.ToString(msg.MessageId), err)
		return
	}

	if err := c.deleteMessage(ctx, msg); err != nil {
		log.Printf("sqsconsumer: failed to delete message %s: %v",
			aws.ToString(msg.MessageId), err)
	}
}

// deleteMessage removes a successfully processed message from the queue.
func (c *Consumer) deleteMessage(ctx context.Context, msg types.Message) error {
	_, err := c.client.DeleteMessage(ctx, &sqs.DeleteMessageInput{
		QueueUrl:      aws.String(c.queueURL),
		ReceiptHandle: msg.ReceiptHandle,
	})
	if err != nil {
		return fmt.Errorf("DeleteMessage: %w", err)
	}
	return nil
}

// snsEnvelope is the JSON wrapper SNS adds around messages delivered to SQS.
type snsEnvelope struct {
	Type    string `json:"Type"`
	Message string `json:"Message"`
}

// unwrapSNS extracts the inner payload from an SNS-to-SQS notification.
// Returns an error (and leaves body unchanged) if the input is not an SNS envelope.
func unwrapSNS(body string) (string, error) {
	var env snsEnvelope
	if err := json.Unmarshal([]byte(body), &env); err != nil {
		return "", err
	}
	if env.Type != "Notification" || env.Message == "" {
		return "", fmt.Errorf("not an SNS notification envelope")
	}
	return env.Message, nil
}
