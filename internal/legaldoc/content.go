package legaldoc

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"unicode"
	"unicode/utf8"
)

type Content struct {
	Title              string    `json:"title"`
	DateNote           string    `json:"date_note,omitempty"`
	Intro              string    `json:"intro,omitempty"`
	Sections           []Section `json:"sections"`
	ConsentHeading     string    `json:"consent_heading"`
	ConsentInstruction string    `json:"consent_instruction,omitempty"`
	ConsentStatements  []string  `json:"consent_statements"`
}

type Section struct {
	Heading string  `json:"heading"`
	Fields  []Field `json:"fields,omitempty"`
	Blocks  []Block `json:"blocks,omitempty"`
}

type Field struct {
	Label string `json:"label"`
	Value string `json:"value"`
}

type Block struct {
	Text  string   `json:"text"`
	Items []string `json:"items,omitempty"`
}

var ErrInvalidContent = errors.New("isi dokumen tidak valid")

const (
	maxContentBytes   = 200 * 1024
	maxSections       = 60
	maxBlocks         = 200
	maxItems          = 100
	maxStatements     = 5
	maxShortText      = 300
	maxParagraphText  = 5000
	maxStatementText  = 600
	maxDocumentNumber = 100
)

func ParseContent(raw []byte) (*Content, error) {
	if len(raw) == 0 || len(raw) > maxContentBytes {
		return nil, fmt.Errorf("%w: ukuran isi dokumen tidak valid", ErrInvalidContent)
	}
	dec := json.NewDecoder(strings.NewReader(string(raw)))
	dec.DisallowUnknownFields()
	var c Content
	if err := dec.Decode(&c); err != nil {
		return nil, fmt.Errorf("%w: struktur data dokumen tidak sesuai", ErrInvalidContent)
	}
	c.normalize()
	if err := c.Validate(); err != nil {
		return nil, err
	}
	return &c, nil
}

func (c *Content) normalize() {
	c.Title = strings.TrimSpace(c.Title)
	c.DateNote = strings.TrimSpace(c.DateNote)
	c.Intro = strings.TrimSpace(c.Intro)
	c.ConsentHeading = strings.TrimSpace(c.ConsentHeading)
	c.ConsentInstruction = strings.TrimSpace(c.ConsentInstruction)
	for i := range c.Sections {
		s := &c.Sections[i]
		s.Heading = strings.TrimSpace(s.Heading)
		for j := range s.Fields {
			s.Fields[j].Label = strings.TrimSpace(s.Fields[j].Label)
			s.Fields[j].Value = strings.TrimSpace(s.Fields[j].Value)
		}
		for j := range s.Blocks {
			s.Blocks[j].Text = strings.TrimSpace(s.Blocks[j].Text)
			for k := range s.Blocks[j].Items {
				s.Blocks[j].Items[k] = strings.TrimSpace(s.Blocks[j].Items[k])
			}
		}
	}
	for i := range c.ConsentStatements {
		c.ConsentStatements[i] = strings.TrimSpace(c.ConsentStatements[i])
	}
}

func (c *Content) Validate() error {
	bad := func(format string, a ...interface{}) error {
		return fmt.Errorf("%w: %s", ErrInvalidContent, fmt.Sprintf(format, a...))
	}
	if err := checkText("judul", c.Title, maxShortText, true); err != nil {
		return err
	}
	if err := checkText("catatan tanggal", c.DateNote, maxShortText, false); err != nil {
		return err
	}
	if err := checkText("pengantar", c.Intro, maxParagraphText, false); err != nil {
		return err
	}
	if len(c.Sections) == 0 || len(c.Sections) > maxSections {
		return bad("jumlah bagian harus 1–%d", maxSections)
	}
	blocks := 0
	for i, s := range c.Sections {
		if err := checkText(fmt.Sprintf("judul bagian %d", i+1), s.Heading, maxShortText, true); err != nil {
			return err
		}
		if len(s.Fields) == 0 && len(s.Blocks) == 0 {
			return bad("bagian %d tidak memiliki isi", i+1)
		}
		for j, f := range s.Fields {
			if err := checkText(fmt.Sprintf("label bagian %d baris %d", i+1, j+1), f.Label, maxShortText, true); err != nil {
				return err
			}
			if err := checkText(fmt.Sprintf("nilai bagian %d baris %d", i+1, j+1), f.Value, maxParagraphText, true); err != nil {
				return err
			}
		}
		for j, b := range s.Blocks {
			blocks++
			if err := checkText(fmt.Sprintf("bagian %d butir %d", i+1, j+1), b.Text, maxParagraphText, true); err != nil {
				return err
			}
			if len(b.Items) > maxItems {
				return bad("bagian %d butir %d memiliki terlalu banyak sub-butir", i+1, j+1)
			}
			for k, it := range b.Items {
				if err := checkText(fmt.Sprintf("bagian %d butir %d sub-butir %d", i+1, j+1, k+1), it, maxParagraphText, true); err != nil {
					return err
				}
			}
		}
	}
	if blocks > maxBlocks {
		return bad("jumlah butir melebihi %d", maxBlocks)
	}
	if err := checkText("judul persetujuan", c.ConsentHeading, maxShortText, true); err != nil {
		return err
	}
	if err := checkText("instruksi persetujuan", c.ConsentInstruction, maxShortText, false); err != nil {
		return err
	}
	if len(c.ConsentStatements) == 0 || len(c.ConsentStatements) > maxStatements {
		return bad("pernyataan persetujuan harus 1–%d butir", maxStatements)
	}
	for i, st := range c.ConsentStatements {
		if err := checkText(fmt.Sprintf("pernyataan persetujuan %d", i+1), st, maxStatementText, true); err != nil {
			return err
		}
	}
	return nil
}

func checkText(name, s string, max int, required bool) error {
	if s == "" {
		if required {
			return fmt.Errorf("%w: %s wajib diisi", ErrInvalidContent, name)
		}
		return nil
	}
	if !utf8.ValidString(s) {
		return fmt.Errorf("%w: %s bukan UTF-8 valid", ErrInvalidContent, name)
	}
	if utf8.RuneCountInString(s) > max {
		return fmt.Errorf("%w: %s melebihi %d karakter", ErrInvalidContent, name, max)
	}
	for _, r := range s {
		if !SupportedRune(r) {
			return fmt.Errorf("%w: %s berisi karakter yang tidak didukung (U+%04X)", ErrInvalidContent, name, r)
		}
	}
	return nil
}

func SupportedRune(r rune) bool {
	switch {
	case r == '\n':
		return true
	case r < 0x20 || (r >= 0x7f && r < 0xa0):
		return false
	case r <= 0x024F: // Basic Latin … Latin Extended-B
		return unicode.IsPrint(r) || r == 0xa0
	case r >= 0x2010 && r <= 0x2027: // dashes, quotes, bullet, ellipsis
		return true
	case r == 0x2030 || r == 0x2039 || r == 0x203A || r == 0x20AC || r == 0x2116 || r == 0x2122:
		return true
	}
	return false
}

func (c *Content) CanonicalJSON() ([]byte, error) {
	return json.Marshal(c)
}

func (c *Content) SHA256() (string, error) {
	b, err := c.CanonicalJSON()
	if err != nil {
		return "", err
	}
	sum := sha256.Sum256(b)
	return hex.EncodeToString(sum[:]), nil
}

func (c *Content) PlainTextSegments() []string {
	out := []string{c.Title}
	if c.DateNote != "" {
		out = append(out, c.DateNote)
	}
	if c.Intro != "" {
		out = append(out, c.Intro)
	}
	for _, s := range c.Sections {
		out = append(out, s.Heading)
		for _, f := range s.Fields {
			out = append(out, f.Label, f.Value)
		}
		for _, b := range s.Blocks {
			out = append(out, b.Text)
			out = append(out, b.Items...)
		}
	}
	out = append(out, c.ConsentHeading)
	if c.ConsentInstruction != "" {
		out = append(out, c.ConsentInstruction)
	}
	out = append(out, c.ConsentStatements...)
	return out
}

func ValidDocumentNumber(s string) error {
	return checkText("nomor dokumen", strings.TrimSpace(s), maxDocumentNumber, false)
}
