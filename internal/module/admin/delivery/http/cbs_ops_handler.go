package http

import (
	"net/http"

	"mbanking-bpr/internal/cbsprovider"
	"mbanking-bpr/pkg/response"

	"github.com/gin-gonic/gin"
)

// CBSOpsHandler exposes Core Banking operational endpoints to SUPER_ADMIN only
// (formerly public — audit DMB-023). Upstream error details are never returned.
type CBSOpsHandler struct {
	cbs cbsprovider.CBSProvider
}

func NewCBSOpsHandler(cbs cbsprovider.CBSProvider) *CBSOpsHandler {
	return &CBSOpsHandler{cbs: cbs}
}

func (h *CBSOpsHandler) Health(c *gin.Context) {
	status, err := h.cbs.Ping(c.Request.Context())
	if err != nil {
		response.Error(c, http.StatusBadGateway, "Core Banking tidak dapat dihubungi", "CBS_UNREACHABLE", nil)
		return
	}
	response.Success(c, "Koneksi Core Banking System (CBS) OpenAPI sehat", status)
}

func (h *CBSOpsHandler) RefreshToken(c *gin.Context) {
	if err := h.cbs.RefreshToken(c.Request.Context()); err != nil {
		response.Error(c, http.StatusBadGateway, "Refresh token CBS gagal", "CBS_TOKEN_REFRESH_FAILED", nil)
		return
	}
	response.Success(c, "Refresh Token OAuth2 CBS OpenAPI berhasil diperbarui", nil)
}
