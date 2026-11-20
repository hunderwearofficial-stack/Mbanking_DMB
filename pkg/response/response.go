package response

import (
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
)

const (
	CodeSuccess            = "00"
	CodeUnauthorized       = "01"
	CodeInvalidCredentials = "02"
	CodeBadRequest         = "03"
	CodeNotFound           = "04"
	CodeRateLimitExceeded  = "06"
	CodeInternalError      = "99"
)

type StandardBankingResponse struct {
	Success      bool        `json:"success"`
	ResponseCode string      `json:"response_code"`
	Message      string      `json:"message"`
	Data         interface{} `json:"data,omitempty"`
	Errors       interface{} `json:"errors,omitempty"`
	Timestamp    string      `json:"timestamp"`
}

func Success(c *gin.Context, message string, data interface{}) {
	c.JSON(http.StatusOK, StandardBankingResponse{
		Success:      true,
		ResponseCode: CodeSuccess,
		Message:      message,
		Data:         data,
		Timestamp:    time.Now().Format(time.RFC3339),
	})
}

func BadRequest(c *gin.Context, message string, errors interface{}) {
	c.JSON(http.StatusBadRequest, StandardBankingResponse{
		Success:      false,
		ResponseCode: CodeBadRequest,
		Message:      message,
		Errors:       errors,
		Timestamp:    time.Now().Format(time.RFC3339),
	})
}

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

func NotFound(c *gin.Context, message string) {
	c.JSON(http.StatusNotFound, StandardBankingResponse{
		Success:      false,
		ResponseCode: CodeNotFound,
		Message:      message,
		Timestamp:    time.Now().Format(time.RFC3339),
	})
}

func TooManyRequests(c *gin.Context, message string) {
	c.JSON(http.StatusTooManyRequests, StandardBankingResponse{
		Success:      false,
		ResponseCode: CodeRateLimitExceeded,
		Message:      message,
		Timestamp:    time.Now().Format(time.RFC3339),
	})
}

func Error(c *gin.Context, httpStatus int, message string, responseCode string, errors interface{}) {
	ErrorWithCode(c, httpStatus, responseCode, message, errors)
}

func ErrorWithCode(c *gin.Context, httpStatus int, responseCode, message string, errors interface{}) {
	c.JSON(httpStatus, StandardBankingResponse{
		Success:      false,
		ResponseCode: responseCode,
		Message:      message,
		Errors:       errors,
		Timestamp:    time.Now().Format(time.RFC3339),
	})
}
