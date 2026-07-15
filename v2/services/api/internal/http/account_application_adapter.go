package httpapi

import (
	"context"

	"github.com/clovery/clovery/services/api/internal/account"
)

type accountProfileReader interface {
	GetProfile(ctx context.Context, accountID string) (account.Profile, error)
}

type accountDeletionRequester interface {
	Request(ctx context.Context, accountID string) (account.DeletionRequest, error)
}

type accountApplicationAdapter struct {
	profiles  accountProfileReader
	deletions accountDeletionRequester
}

func NewAccountApplication(
	profiles accountProfileReader,
	deletions accountDeletionRequester,
) AccountHTTPApplication {
	return &accountApplicationAdapter{profiles: profiles, deletions: deletions}
}

func (adapter *accountApplicationAdapter) GetAccount(
	ctx context.Context,
	accountID string,
) (AccountSummary, error) {
	profile, err := adapter.profiles.GetProfile(ctx, accountID)
	if err != nil {
		return AccountSummary{}, err
	}
	bindings := make([]AccountBindingSummary, 0, len(profile.Bindings))
	for _, binding := range profile.Bindings {
		bindings = append(bindings, AccountBindingSummary{
			Provider: binding.Provider, Issuer: binding.Issuer, CreatedAt: binding.CreatedAt,
		})
	}
	return AccountSummary{
		AccountID:              profile.AccountID,
		CloveryID:              profile.CloveryID,
		Status:                 profile.Status,
		CreatedAt:              profile.CreatedAt,
		HasPassword:            profile.HasPassword,
		PasskeyCount:           profile.PasskeyCount,
		RecoveryCodesRemaining: profile.RecoveryCodeCount,
		Bindings:               bindings,
	}, nil
}

func (adapter *accountApplicationAdapter) RequestDeletion(
	ctx context.Context,
	accountID string,
) (DeletionRequestSummary, error) {
	request, err := adapter.deletions.Request(ctx, accountID)
	return DeletionRequestSummary{
		ID:           request.ID,
		Status:       request.Status,
		RequestedAt:  request.RequestedAt,
		ScheduledFor: request.ScheduledFor,
	}, err
}
