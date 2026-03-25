package handler

import "context"

// Handler processes risk monitoring messages from the high-priority SQS queue.
type Handler struct{}

func New() *Handler {
	return &Handler{}
}

func (h *Handler) Handle(ctx context.Context, body string) error {
	return nil
}
