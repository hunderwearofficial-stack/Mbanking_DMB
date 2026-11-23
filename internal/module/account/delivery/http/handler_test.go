package http

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"mbanking-bpr/internal/cbsprovider"
	"mbanking-bpr/internal/domain"
	"mbanking-bpr/internal/module/account/service"

	"github.com/gin-gonic/gin"
)

type fakeAccountService struct {
	service.AccountService
	err error
}

func (f *fakeAccountService) GetBalance(context.Context, service.Caller, string) (*domain.BalanceResponse, error) {
	return nil, f.err
}

func (f *fakeAccountService) GetMutations(context.Context, service.Caller, domain.MutationQueryParam) (string, []domain.Mutation, bool, error) {
	return "", nil, false, f.err
}

func (f *fakeAccountService) GetLoans(context.Context, service.Caller) ([]domain.DMBLoanAccountItem, error) {
	return nil, f.err
}

func (f *fakeAccountService) GetProductsCatalog(context.Context) (*domain.DMBProductsCatalog, error) {
	return nil, f.err
}

func call(t *testing.T, svcErr error, path string, h func(*AccountHandler) gin.HandlerFunc) (int, map[string]interface{}) {
	t.Helper()
	gin.SetMode(gin.TestMode)
	r := gin.New()
	r.GET("/x", h(NewAccountHandler(&fakeAccountService{err: svcErr})))
	w := httptest.NewRecorder()
	r.ServeHTTP(w, httptest.NewRequest(http.MethodGet, path, nil))
	var body map[string]interface{}
	_ = json.Unmarshal(w.Body.Bytes(), &body)
	return w.Code, body
}

func TestCBSOutageIsReportedAsServiceDisruption(t *testing.T) {
	outage := errors.New("dial tcp 10.0.0.5:443: i/o timeout")
	handlers := map[string]func(*AccountHandler) gin.HandlerFunc{
		"balance":   func(h *AccountHandler) gin.HandlerFunc { return h.GetBalance },
		"mutations": func(h *AccountHandler) gin.HandlerFunc { return h.GetMutations },
		"loans":     func(h *AccountHandler) gin.HandlerFunc { return h.GetLoans },
		"products":  func(h *AccountHandler) gin.HandlerFunc { return h.GetProducts },
	}
	for name, h := range handlers {
		for _, err := range []error{outage, cbsprovider.ErrCBSUnavailable} {
			code, body := call(t, err, "/x", h)
			if code != http.StatusServiceUnavailable {
				t.Errorf("%s: got %d, want 503", name, code)
			}
			if body["data"] != nil {
				t.Errorf("%s: response must not carry data on outage: %v", name, body["data"])
			}
			msg, _ := body["message"].(string)
			if !strings.Contains(msg, "belum dapat ditampilkan") || strings.Contains(msg, "10.0.0.5") {
				t.Errorf("%s: unexpected user message %q", name, msg)
			}
		}
	}
}

func TestNotFoundAndForbiddenAreDistinct(t *testing.T) {
	balance := func(h *AccountHandler) gin.HandlerFunc { return h.GetBalance }
	if code, _ := call(t, cbsprovider.ErrAccountNotFound, "/x", balance); code != http.StatusNotFound {
		t.Errorf("not found: got %d, want 404", code)
	}
	if code, _ := call(t, service.ErrForbidden, "/x", balance); code != http.StatusForbidden {
		t.Errorf("forbidden: got %d, want 403", code)
	}
}
