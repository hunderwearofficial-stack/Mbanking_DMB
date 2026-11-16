// Package push sends customer notifications through Firebase Cloud Messaging (HTTP v1),
// manages device tokens, Firebase integration settings and delivery records.
package push

import (
	"bytes"
	"context"
	"crypto/rsa"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

// Google endpoints (overridden only in tests).
const (
	defaultTokenURL = "https://oauth2.googleapis.com/token"
	defaultFCMBase  = "https://fcm.googleapis.com"
	fcmScope        = "https://www.googleapis.com/auth/firebase.messaging"
)

// ErrInvalidCredential is returned for a service-account file that can not be used.
var ErrInvalidCredential = errors.New("credential Firebase tidak valid")

// Credential is the part of a Firebase service-account JSON needed for FCM.
type Credential struct {
	ProjectID   string
	ClientEmail string
	key         *rsa.PrivateKey
	Fingerprint string // SHA-256 of the private key id + client email (not secret)
}

// ParseCredential validates a service-account JSON. Nothing from it is logged.
func ParseCredential(raw []byte) (*Credential, error) {
	if len(raw) == 0 || len(raw) > 16*1024 {
		return nil, fmt.Errorf("%w: ukuran berkas tidak wajar", ErrInvalidCredential)
	}
	var sa struct {
		Type         string `json:"type"`
		ProjectID    string `json:"project_id"`
		PrivateKeyID string `json:"private_key_id"`
		PrivateKey   string `json:"private_key"`
		ClientEmail  string `json:"client_email"`
	}
	if err := json.Unmarshal(raw, &sa); err != nil {
		return nil, fmt.Errorf("%w: bukan JSON service account", ErrInvalidCredential)
	}
	if sa.Type != "service_account" || sa.ProjectID == "" || sa.ClientEmail == "" || sa.PrivateKey == "" {
		return nil, fmt.Errorf("%w: harus berkas service account Firebase (type, project_id, client_email, private_key)", ErrInvalidCredential)
	}
	if !strings.HasSuffix(sa.ClientEmail, ".iam.gserviceaccount.com") {
		return nil, fmt.Errorf("%w: client_email bukan akun layanan Google", ErrInvalidCredential)
	}
	key, err := jwt.ParseRSAPrivateKeyFromPEM([]byte(sa.PrivateKey))
	if err != nil {
		return nil, fmt.Errorf("%w: private key tidak dapat dibaca", ErrInvalidCredential)
	}
	sum := sha256.Sum256([]byte(sa.PrivateKeyID + "|" + sa.ClientEmail))
	return &Credential{ProjectID: sa.ProjectID, ClientEmail: sa.ClientEmail, key: key, Fingerprint: hex.EncodeToString(sum[:])}, nil
}

// SendError is a classified FCM failure.
type SendError struct {
	HTTPStatus int
	Code       string // FCM error code, e.g. UNREGISTERED, INVALID_ARGUMENT, UNAVAILABLE
	Message    string
}

func (e *SendError) Error() string {
	return fmt.Sprintf("FCM %d %s: %s", e.HTTPStatus, e.Code, e.Message)
}

// InvalidToken: the registration token is no longer valid and must be removed.
func (e *SendError) InvalidToken() bool {
	return e.Code == "UNREGISTERED" || (e.HTTPStatus == http.StatusNotFound && e.Code == "NOT_FOUND")
}

// Retryable: temporary condition on the FCM side.
func (e *SendError) Retryable() bool {
	return e.HTTPStatus == http.StatusTooManyRequests || e.HTTPStatus >= 500 || e.Code == "UNAVAILABLE" || e.Code == "INTERNAL" || e.Code == "QUOTA_EXCEEDED"
}

// AuthProblem: the credential or project is not accepted.
func (e *SendError) AuthProblem() bool {
	return e.HTTPStatus == http.StatusUnauthorized || e.HTTPStatus == http.StatusForbidden ||
		e.Code == "SENDER_ID_MISMATCH" || e.Code == "THIRD_PARTY_AUTH_ERROR" || e.Code == "PERMISSION_DENIED"
}

// Message is what is sent to one device. Only generic, non-sensitive text is allowed
// here (see notification.PushBody); details stay in the in-app inbox.
type Message struct {
	Token    string
	Title    string
	Body     string
	Category string
	Ref      string // delivery id, echoed back by the app when the notification is opened
}

// Client talks to FCM HTTP v1 with one service account.
type Client struct {
	cred     *Credential
	http     *http.Client
	tokenURL string
	fcmBase  string

	mu          sync.Mutex
	accessToken string
	expiresAt   time.Time
}

// NewClient creates a client; tokenURL/fcmBase empty = Google production endpoints.
func NewClient(cred *Credential, tokenURL, fcmBase string) *Client {
	if tokenURL == "" {
		tokenURL = defaultTokenURL
	}
	if fcmBase == "" {
		fcmBase = defaultFCMBase
	}
	return &Client{cred: cred, tokenURL: tokenURL, fcmBase: strings.TrimRight(fcmBase, "/"), http: &http.Client{Timeout: 10 * time.Second}}
}

// token returns a cached OAuth2 access token (JWT bearer grant, RS256).
func (c *Client) token(ctx context.Context) (string, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.accessToken != "" && time.Until(c.expiresAt) > time.Minute {
		return c.accessToken, nil
	}
	now := time.Now()
	assertion, err := jwt.NewWithClaims(jwt.SigningMethodRS256, jwt.MapClaims{
		"iss": c.cred.ClientEmail, "scope": fcmScope, "aud": defaultTokenURL,
		"iat": now.Unix(), "exp": now.Add(50 * time.Minute).Unix(),
	}).SignedString(c.cred.key)
	if err != nil {
		return "", fmt.Errorf("%w: gagal menandatangani permintaan token", ErrInvalidCredential)
	}
	form := url.Values{"grant_type": {"urn:ietf:params:oauth:grant-type:jwt-bearer"}, "assertion": {assertion}}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.tokenURL, strings.NewReader(form.Encode()))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	resp, err := c.http.Do(req)
	if err != nil {
		return "", &SendError{Code: "UNAVAILABLE", Message: "server otorisasi Google tidak dapat dihubungi"}
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(io.LimitReader(resp.Body, 64*1024))
	var tr struct {
		AccessToken string `json:"access_token"`
		ExpiresIn   int    `json:"expires_in"`
		Error       string `json:"error"`
		Description string `json:"error_description"`
	}
	_ = json.Unmarshal(body, &tr)
	if resp.StatusCode != http.StatusOK || tr.AccessToken == "" {
		msg := tr.Description
		if msg == "" {
			msg = "service account ditolak oleh Google"
		}
		return "", &SendError{HTTPStatus: http.StatusUnauthorized, Code: strings.ToUpper(firstNonEmpty(tr.Error, "UNAUTHENTICATED")), Message: msg}
	}
	c.accessToken = tr.AccessToken
	c.expiresAt = now.Add(time.Duration(tr.ExpiresIn) * time.Second)
	return c.accessToken, nil
}

func firstNonEmpty(v ...string) string {
	for _, s := range v {
		if s != "" {
			return s
		}
	}
	return ""
}

// AndroidChannelID must equal the channel created by the Flutter app.
const AndroidChannelID = "dmb_notification_channel"

// Send delivers one message. validateOnly asks FCM to validate without delivering.
// It returns the FCM message name on acceptance.
func (c *Client) Send(ctx context.Context, m Message, validateOnly bool) (string, error) {
	tok, err := c.token(ctx)
	if err != nil {
		return "", err
	}
	payload := map[string]interface{}{
		"validate_only": validateOnly,
		"message": map[string]interface{}{
			"token":        m.Token,
			"notification": map[string]string{"title": m.Title, "body": m.Body},
			"data":         map[string]string{"category": m.Category, "ref": m.Ref, "route": "notifications"},
			"android": map[string]interface{}{
				"priority":     "HIGH",
				"notification": map[string]string{"channel_id": AndroidChannelID, "sound": "default"},
			},
			"apns": map[string]interface{}{"payload": map[string]interface{}{"aps": map[string]string{"sound": "default"}}},
		},
	}
	raw, _ := json.Marshal(payload)
	endpoint := fmt.Sprintf("%s/v1/projects/%s/messages:send", c.fcmBase, url.PathEscape(c.cred.ProjectID))
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(raw))
	if err != nil {
		return "", err
	}
	req.Header.Set("Authorization", "Bearer "+tok)
	req.Header.Set("Content-Type", "application/json")
	resp, err := c.http.Do(req)
	if err != nil {
		return "", &SendError{Code: "UNAVAILABLE", Message: "FCM tidak dapat dihubungi"}
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(io.LimitReader(resp.Body, 64*1024))
	if resp.StatusCode == http.StatusOK {
		var ok struct {
			Name string `json:"name"`
		}
		_ = json.Unmarshal(body, &ok)
		return ok.Name, nil
	}
	var fe struct {
		Error struct {
			Status  string `json:"status"`
			Message string `json:"message"`
			Details []struct {
				ErrorCode string `json:"errorCode"`
			} `json:"details"`
		} `json:"error"`
	}
	_ = json.Unmarshal(body, &fe)
	code := fe.Error.Status
	for _, d := range fe.Error.Details {
		if d.ErrorCode != "" {
			code = d.ErrorCode
		}
	}
	if resp.StatusCode == http.StatusUnauthorized {
		c.mu.Lock()
		c.accessToken = ""
		c.mu.Unlock()
	}
	msg := fe.Error.Message
	if len(msg) > 300 {
		msg = msg[:300]
	}
	return "", &SendError{HTTPStatus: resp.StatusCode, Code: firstNonEmpty(code, "UNKNOWN"), Message: msg}
}
