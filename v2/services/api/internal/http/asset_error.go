package httpapi

import (
	"errors"
	"net/http"

	"github.com/clovery/clovery/services/api/internal/asset"
)

func writeAssetError(responseWriter http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, asset.ErrInvalidAsset):
		writeAPIError(responseWriter, http.StatusBadRequest, "invalid_asset", "The asset metadata is invalid.")
	case errors.Is(err, asset.ErrAssetMetadataMismatch):
		writeAPIError(responseWriter, http.StatusConflict, "asset_id_reused", "The asset ID was already used.")
	case errors.Is(err, asset.ErrIntegrityMismatch):
		writeAPIError(responseWriter, http.StatusUnprocessableEntity, "asset_integrity_mismatch", "The uploaded asset failed verification.")
	case errors.Is(err, asset.ErrAssetNotReady):
		writeAPIError(responseWriter, http.StatusConflict, "asset_not_ready", "The asset is not ready.")
	case errors.Is(err, asset.ErrAssetNotFound):
		writeAPIError(responseWriter, http.StatusNotFound, "asset_not_found", "The asset was not found.")
	default:
		writeManagementError(responseWriter, err)
	}
}
