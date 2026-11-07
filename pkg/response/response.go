package response

import (
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
)

// Response Code Constants following standard banking / middleware convention
const (
	CodeSuccess               = "00"
	CodeUnauthorized          = "01"
	CodeInvalidCredentials    = "02"
	CodeBadRequest            = "03"
	CodeNotFound              = "04"
	CodeInsufficientBalance   = "05"
	CodeRateLimitExceeded     = "06"
	CodeInternalError         = "99"
)

// StandardBankingResponse is the JSON envelope for all API responses
type StandardBankingResponse struct {
	Success      bool        `json:"success"`
	ResponseCode string      `json:"response_code"`
	Message      string      `json:"message"`
	Data         interface{} `json:"data,omitempty"`
	Errors       interface{} `json:"errors,omitempty"`
	Timestamp    string      `json:"timestamp"`
}

// Success sends an HTTP 200 response with banking CodeSuccess
func Success(c *gin.Context, message string, data interface{}) {
	c.JSON(http.StatusOK, StandardBankingResponse{
		Success:      true,
		ResponseCode: CodeSuccess,
		Message:      message,
		Data:         data,
		Timestamp:    time.Now().Format(time.RFC3339),
	})
}

// Created sends an HTTP 201 response with banking CodeSuccess
func Created(c *gin.Context, message string, data interface{}) {
	c.JSON(http.StatusCreated, StandardBankingResponse{
		Success:      true,
		ResponseCode: CodeSuccess,
		Message:      message,
		Data:         data,
		Timestamp:    time.Now().Format(time.RFC3339),
	})
}

// BadRequest sends an HTTP 400 error response
func BadRequest(c *gin.Context, message string, errors interface{}) {
	c.JSON(http.StatusBadRequest, StandardBankingResponse{
		Success:      false,
		ResponseCode: CodeBadRequest,
		Message:      message,
		Errors:       errors,
		Timestamp:    time.Now().Format(time.RFC3339),
	})
}

// Unauthorized sends an HTTP 401 error response
func Unauthorized(c *gin.Context, responseCode, message string) {
	if responseCode == "" {
		responseCode = CodeUnauthorized
	}
	c.JSON(http.StatusUnauthorized, StandardBankingResponse{
		Success:      false,
		ResponseCode: responseCode,
		Message:      message,
		Timestamp:    time.Now().Format(time.RFC3339),
	})
}

// NotFound sends an HTTP 404 error response
func NotFound(c *gin.Context, message string) {
	c.JSON(http.StatusNotFound, StandardBankingResponse{
		Success:      false,
		ResponseCode: CodeNotFound,
		Message:      message,
		Timestamp:    time.Now().Format(time.RFC3339),
	})
}

// TooManyRequests sends an HTTP 429 error response (Rate Limiter)
func TooManyRequests(c *gin.Context, message string) {
	c.JSON(http.StatusTooManyRequests, StandardBankingResponse{
		Success:      false,
		ResponseCode: CodeRateLimitExceeded,
		Message:      message,
		Timestamp:    time.Now().Format(time.RFC3339),
	})
}

// Error sends a customized error response
func Error(c *gin.Context, httpStatus int, message string, responseCode string, errors interface{}) {
	ErrorWithCode(c, httpStatus, responseCode, message, errors)
}

// ErrorWithCode sends a customized error response with specific HTTP status and response code
func ErrorWithCode(c *gin.Context, httpStatus int, responseCode, message string, errors interface{}) {
	c.JSON(httpStatus, StandardBankingResponse{
		Success:      false,
		ResponseCode: responseCode,
		Message:      message,
		Errors:       errors,
		Timestamp:    time.Now().Format(time.RFC3339),
	})
}

// InternalServerError sends an HTTP 500 error response
func InternalServerError(c *gin.Context, message string) {
	c.JSON(http.StatusInternalServerError, StandardBankingResponse{
		Success:      false,
		ResponseCode: CodeInternalError,
		Message:      message,
		Timestamp:    time.Now().Format(time.RFC3339),
	})
}

