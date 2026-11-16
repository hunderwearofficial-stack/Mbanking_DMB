package http

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"mbanking-bpr/internal/cbsprovider"
	"mbanking-bpr/internal/module/transaction/service"

	"github.com/gin-gonic/gin"
)

type fakeTxService struct{ err error }

func (f *fakeTxService) Transfer(context.Context, service.TransferInput) (*service.TransferResult, error) {
	return &service.TransferResult{RequestID: "req-123"}, f.err
}

func transfer(t *testing.T, svcErr error) (int, map[string]interface{}) {
	t.Helper()
	gin.SetMode(gin.TestMode)
	r := gin.New()
	r.POST("/t", NewTransactionHandler(&fakeTxService{err: svcErr}).Transfer)
	body := `{"to_bank_code":"DMB","to_account":"0010100000002","amount":15000,"pin":"582913"}`
	w := httptest.NewRecorder()
	r.ServeHTTP(w, httptest.NewRequest(http.MethodPost, "/t", strings.NewReader(body)))
	var out map[string]interface{}
	_ = json.Unmarshal(w.Body.Bytes(), &out)
	return w.Code, out
}

// The customer notification must match the real transaction state (audit DMB-015).
func TestTransferOutcomeMapping(t *testing.T) {
	cases := []struct {
		name     string
		err      error
		status   int
		contains string
	}{
		{"unknown outcome is 'being verified', not 'failed'", service.ErrOutcomeUnknown, http.StatusAccepted, "sedang diverifikasi"},
		{"CBS rejection says funds were not debited", fmt.Errorf("%w: limit", cbsprovider.ErrCBSRejected), http.StatusUnprocessableEntity, "tidak terdebet"},
		{"business rejection shows its message", service.ErrInvalidAmount, http.StatusBadRequest, "nominal transfer tidak valid"},
		{"internal failure is generic", errors.New("pq: connection refused 10.1.2.3"), http.StatusServiceUnavailable, "Layanan sedang mengalami gangguan"},
		{"service unavailable", service.ErrServiceUnavailable, http.StatusServiceUnavailable, "tidak tersedia"},
	}
	for _, c := range cases {
		code, body := transfer(t, c.err)
		msg, _ := body["message"].(string)
		if code != c.status || !strings.Contains(msg, c.contains) {
			t.Errorf("%s: got %d %q, want %d containing %q", c.name, code, msg, c.status, c.contains)
		}
		if strings.Contains(msg, "10.1.2.3") || strings.Contains(msg, "pq:") {
			t.Errorf("%s: internal details leaked: %q", c.name, msg)
		}
		if body["data"] != nil {
			t.Errorf("%s: failed/unknown transfer must not return a success payload", c.name)
		}
	}
}
