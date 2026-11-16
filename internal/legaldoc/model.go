package legaldoc

import "time"

// Document identifiers.
const DocMobileTerms = "MOBILE_BANKING_TERMS"

// Version statuses.
const (
	StatusDraft     = "DRAFT"
	StatusPending   = "PENDING_APPROVAL"
	StatusPublished = "PUBLISHED"
	StatusArchived  = "ARCHIVED"
)

// Consent channels.
const (
	ChannelPreLogin   = "PRE_LOGIN"
	ChannelLogin      = "LOGIN"
	ChannelActivation = "ACTIVATION"
)

// Version maps legal_document_versions.
type Version struct {
	ID             string     `json:"id" gorm:"column:id;primaryKey;default:gen_random_uuid()"`
	DocumentID     string     `json:"document_id" gorm:"column:document_id"`
	VersionNumber  int        `json:"version_number" gorm:"column:version_number"`
	Status         string     `json:"status" gorm:"column:status"`
	DocumentNumber *string    `json:"document_number" gorm:"column:document_number"`
	ChangeSummary  string     `json:"change_summary" gorm:"column:change_summary"`
	Content        string     `json:"-" gorm:"column:content;type:jsonb"`
	ContentSHA256  string     `json:"content_sha256" gorm:"column:content_sha256"`
	DraftPDFSHA256 *string    `json:"draft_pdf_sha256" gorm:"column:draft_pdf_sha256"`
	PDFSHA256      *string    `json:"pdf_sha256" gorm:"column:pdf_sha256"`
	EffectiveFrom  *time.Time `json:"effective_from" gorm:"column:effective_from"`
	CreatedBy      string     `json:"created_by" gorm:"column:created_by"`
	CreatedByName  string     `json:"created_by_name" gorm:"column:created_by_name"`
	CreatedAt      time.Time  `json:"created_at" gorm:"column:created_at;autoCreateTime:false;default:now()"`
	UpdatedAt      time.Time  `json:"updated_at" gorm:"column:updated_at;autoUpdateTime:false;default:now()"`
	SubmittedBy    *string    `json:"submitted_by" gorm:"column:submitted_by"`
	SubmittedAt    *time.Time `json:"submitted_at" gorm:"column:submitted_at"`
	ApprovedBy     *string    `json:"approved_by" gorm:"column:approved_by"`
	ApprovedByName *string    `json:"approved_by_name" gorm:"column:approved_by_name"`
	PublishedAt    *time.Time `json:"published_at" gorm:"column:published_at"`
	ArchivedBy     *string    `json:"archived_by" gorm:"column:archived_by"`
	ArchivedAt     *time.Time `json:"archived_at" gorm:"column:archived_at"`
}

func (Version) TableName() string { return "legal_document_versions" }

// Acceptance maps legal_acceptances (append-only).
type Acceptance struct {
	ID                   string    `json:"id" gorm:"column:id;primaryKey;default:gen_random_uuid()"`
	DocumentID           string    `json:"document_id" gorm:"column:document_id"`
	VersionID            string    `json:"version_id" gorm:"column:version_id"`
	VersionNumber        int       `json:"version_number" gorm:"column:version_number"`
	UserID               *string   `json:"user_id" gorm:"column:user_id"`
	DeviceID             string    `json:"-" gorm:"column:device_id"`
	Channel              string    `json:"channel" gorm:"column:channel"`
	Status               string    `json:"status" gorm:"column:status;default:ACCEPTED"`
	PreLoginAcceptanceID *string   `json:"pre_login_acceptance_id" gorm:"column:pre_login_acceptance_id"`
	PDFSHA256            string    `json:"pdf_sha256" gorm:"column:pdf_sha256"`
	AcceptedAt           time.Time `json:"accepted_at" gorm:"column:accepted_at;autoCreateTime:false;default:now()"`
	IPAddress            string    `json:"ip_address" gorm:"column:ip_address"`
	UserAgent            string    `json:"user_agent" gorm:"column:user_agent"`
}

func (Acceptance) TableName() string { return "legal_acceptances" }
