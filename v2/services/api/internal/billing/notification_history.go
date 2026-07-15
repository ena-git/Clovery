package billing

import (
	"context"
	"fmt"
	"time"
)

const maximumNotificationHistoryPages = 10000

type NotificationHistoryQuery struct {
	StartAt         time.Time
	EndAt           time.Time
	Environment     Environment
	OnlyFailures    bool
	PaginationToken string
}

type NotificationHistoryPage struct {
	SignedPayloads  []string
	HasMore         bool
	PaginationToken string
}

type notificationHistorySource interface {
	FetchNotificationHistoryPage(
		ctx context.Context,
		query NotificationHistoryQuery,
	) (NotificationHistoryPage, error)
}

func (service *Service) ReplayNotificationHistory(
	ctx context.Context,
	query NotificationHistoryQuery,
) (int, error) {
	source, ok := service.verifier.(notificationHistorySource)
	if !ok || query.StartAt.IsZero() || query.EndAt.IsZero() ||
		!query.StartAt.Before(query.EndAt) || !query.Environment.Valid() {
		return 0, ErrInvalidRequest
	}
	processed := 0
	seenTokens := make(map[string]struct{})
	for pageNumber := 0; pageNumber < maximumNotificationHistoryPages; pageNumber++ {
		page, err := source.FetchNotificationHistoryPage(ctx, query)
		if err != nil {
			return processed, err
		}
		for _, signedPayload := range page.SignedPayloads {
			if err := service.ProcessAppleNotification(ctx, signedPayload); err != nil {
				return processed, fmt.Errorf("replay Apple notification history: %w", err)
			}
			processed++
		}
		if !page.HasMore {
			return processed, nil
		}
		if page.PaginationToken == "" {
			return processed, ErrVerificationFailed
		}
		if _, duplicate := seenTokens[page.PaginationToken]; duplicate {
			return processed, ErrVerificationFailed
		}
		seenTokens[page.PaginationToken] = struct{}{}
		query.PaginationToken = page.PaginationToken
	}
	return processed, ErrVerificationUnavailable
}
