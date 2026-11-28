package pdfdoc

import (
	_ "embed"
	"errors"
	"fmt"
	"strings"
	"time"

	"mbanking-bpr/internal/legaldoc"

	"github.com/signintech/gopdf"
)

//go:embed assets/NotoSans-Regular.ttf
var fontRegular []byte

//go:embed assets/NotoSans-Bold.ttf
var fontBold []byte

//go:embed assets/bank_logo.png
var bankLogo []byte

const (
	BankName        = "Bank DMB"
	BankNameUpper   = "BANK DMB"
	DocumentTitle   = "SYARAT DAN KETENTUAN LAYANAN MOBILE BANKING"
	DocumentShort   = "Syarat dan Ketentuan Layanan Mobile Banking"
	TemplateVersion = "sk-pdf-template/1"
)

type Meta = legaldoc.RenderMeta

func RenderPDF(c *legaldoc.Content, m Meta) ([]byte, error) {
	res, err := Render(c, m)
	if err != nil {
		return nil, err
	}
	return res.PDF, nil
}

type Result struct {
	PDF   []byte
	Pages int
	Text  []string // every rendered text run, in reading order (header/footer excluded)
}

var wib = time.FixedZone("WIB", 7*3600)

var months = [...]string{"Januari", "Februari", "Maret", "April", "Mei", "Juni", "Juli",
	"Agustus", "September", "Oktober", "November", "Desember"}

func FormatDate(t time.Time) string {
	t = t.In(wib)
	return fmt.Sprintf("%d %s %d", t.Day(), months[t.Month()-1], t.Year())
}

func FormatDateTime(t time.Time) string {
	t = t.In(wib)
	return fmt.Sprintf("%s, %02d.%02d WIB", FormatDate(t), t.Hour(), t.Minute())
}

const (
	pageW        = 595.0
	pageH        = 842.0
	marginLeft   = 62.0
	marginRight  = 62.0
	contentTop   = 92.0
	draftTop     = 104.0
	contentBot   = pageH - 66.0
	contentWidth = pageW - marginLeft - marginRight
)

type color struct{ r, g, b uint8 }

var (
	cText    = color{30, 41, 59}
	cMuted   = color{100, 116, 139}
	cHeading = color{13, 98, 89}
	cBrand   = color{10, 59, 102}
	cDraft   = color{185, 28, 28}
	cRule    = color{203, 213, 225}
)

type run struct {
	x     float64
	text  string
	bold  bool
	size  float64
	color color
}

type line struct {
	runs         []run
	height       float64
	spaceBefore  float64
	keepWithNext bool
	rule         bool // horizontal rule instead of text
}

type layout struct {
	pdf     *gopdf.GoPdf
	lines   []line
	glyphMu []rune
}

func (l *layout) setFont(bold bool, size float64) error {
	family := "noto"
	if bold {
		family = "noto-bold"
	}
	return l.pdf.SetFont(family, "", size)
}

func (l *layout) width(text string, bold bool, size float64) (float64, error) {
	if err := l.setFont(bold, size); err != nil {
		return 0, err
	}
	return l.pdf.MeasureTextWidth(text)
}

func (l *layout) wrap(text string, bold bool, size, maxW float64) ([]string, error) {
	var out []string
	for _, para := range strings.Split(text, "\n") {
		words := strings.Fields(para)
		if len(words) == 0 {
			out = append(out, "")
			continue
		}
		cur := ""
		for _, w := range words {
			cand := w
			if cur != "" {
				cand = cur + " " + w
			}
			cw, err := l.width(cand, bold, size)
			if err != nil {
				return nil, err
			}
			if cw <= maxW {
				cur = cand
				continue
			}
			if cur != "" {
				out = append(out, cur)
				cur = ""
			}
			ww, err := l.width(w, bold, size)
			if err != nil {
				return nil, err
			}
			if ww <= maxW {
				cur = w
				continue
			}
			piece := ""
			for _, r := range w {
				pw, err := l.width(piece+string(r), bold, size)
				if err != nil {
					return nil, err
				}
				if pw > maxW && piece != "" {
					out = append(out, piece)
					piece = ""
				}
				piece += string(r)
			}
			cur = piece
		}
		if cur != "" {
			out = append(out, cur)
		}
	}
	return out, nil
}

func (l *layout) paragraph(text string, x float64, bold bool, size float64, c color, spaceBefore float64, keep bool) error {
	lines, err := l.wrap(text, bold, size, contentWidth-(x-marginLeft))
	if err != nil {
		return err
	}
	lh := size * 1.45
	for i, s := range lines {
		ln := line{runs: []run{{x: x, text: s, bold: bold, size: size, color: c}}, height: lh}
		if i == 0 {
			ln.spaceBefore = spaceBefore
			ln.keepWithNext = keep
		}
		if keep && i < len(lines)-1 {
			ln.keepWithNext = true
		}
		l.lines = append(l.lines, ln)
	}
	return nil
}

func (l *layout) row(label, value string, labelW float64, size float64, spaceBefore float64) error {
	colon := ":"
	cw, err := l.width(colon+" ", false, size)
	if err != nil {
		return err
	}
	labelLines, err := l.wrap(label, true, size, labelW-6)
	if err != nil {
		return err
	}
	valueX := marginLeft + labelW + cw
	valueLines, err := l.wrap(value, false, size, contentWidth-labelW-cw)
	if err != nil {
		return err
	}
	n := len(labelLines)
	if len(valueLines) > n {
		n = len(valueLines)
	}
	lh := size * 1.45
	for i := 0; i < n; i++ {
		ln := line{height: lh}
		if i == 0 {
			ln.spaceBefore = spaceBefore
		}
		if i < len(labelLines) {
			ln.runs = append(ln.runs, run{x: marginLeft, text: labelLines[i], bold: true, size: size, color: cText})
		}
		if i == 0 {
			ln.runs = append(ln.runs, run{x: marginLeft + labelW, text: colon, size: size, color: cText})
		}
		if i < len(valueLines) {
			ln.runs = append(ln.runs, run{x: valueX, text: valueLines[i], size: size, color: cText})
		}
		if i < n-1 {
			ln.keepWithNext = true
		}
		l.lines = append(l.lines, ln)
	}
	return nil
}

func (l *layout) rule(spaceBefore float64) {
	l.lines = append(l.lines, line{rule: true, height: 8, spaceBefore: spaceBefore})
}

func Render(c *legaldoc.Content, m Meta) (*Result, error) {
	if c == nil {
		return nil, errors.New("isi dokumen kosong")
	}
	if err := c.Validate(); err != nil {
		return nil, err
	}
	if m.VersionNumber <= 0 {
		return nil, errors.New("nomor versi tidak valid")
	}

	pdf := &gopdf.GoPdf{}
	pdf.Start(gopdf.Config{PageSize: *gopdf.PageSizeA4, Unit: gopdf.UnitPT})
	l := &layout{pdf: pdf}
	onMissing := func(r rune) { l.glyphMu = append(l.glyphMu, r) }
	if err := pdf.AddTTFFontDataWithOption("noto", fontRegular, gopdf.TtfOption{Style: gopdf.Regular, OnGlyphNotFound: onMissing}); err != nil {
		return nil, fmt.Errorf("font: %w", err)
	}
	if err := pdf.AddTTFFontDataWithOption("noto-bold", fontBold, gopdf.TtfOption{Style: gopdf.Regular, OnGlyphNotFound: onMissing}); err != nil {
		return nil, fmt.Errorf("font: %w", err)
	}
	pdf.SetInfo(gopdf.PdfInfo{
		Title:        fmt.Sprintf("%s - Versi %d", DocumentShort, m.VersionNumber),
		Author:       BankName,
		Subject:      DocumentShort,
		Creator:      "MBanking BPR Backoffice (" + TemplateVersion + ")",
		CreationDate: m.GeneratedAt,
	})

	if err := l.paragraph(DocumentTitle, marginLeft, true, 14, cBrand, 0, true); err != nil {
		return nil, err
	}
	metaRows := [][2]string{}
	if strings.TrimSpace(m.DocumentNumber) != "" {
		metaRows = append(metaRows, [2]string{"Nomor Dokumen", strings.TrimSpace(m.DocumentNumber)})
	}
	metaRows = append(metaRows, [2]string{"Versi Dokumen", fmt.Sprintf("%d", m.VersionNumber)})
	if m.PublishedAt != nil {
		metaRows = append(metaRows, [2]string{"Tanggal Penerbitan", FormatDate(*m.PublishedAt)})
	} else {
		metaRows = append(metaRows, [2]string{"Tanggal Penerbitan", "- (draf, belum diterbitkan)"})
	}
	if m.EffectiveFrom != nil {
		metaRows = append(metaRows, [2]string{"Tanggal Mulai Berlaku", FormatDateTime(*m.EffectiveFrom)})
	} else {
		metaRows = append(metaRows, [2]string{"Tanggal Mulai Berlaku", "- (ditetapkan saat diterbitkan)"})
	}
	for i, r := range metaRows {
		sb := 0.0
		if i == 0 {
			sb = 8
		}
		if err := l.row(r[0], r[1], 130, 9, sb); err != nil {
			return nil, err
		}
	}
	l.rule(6)

	if err := l.paragraph(c.Title, marginLeft, true, 12, cText, 6, true); err != nil {
		return nil, err
	}
	if c.DateNote != "" {
		if err := l.paragraph(c.DateNote, marginLeft, false, 9, cMuted, 2, false); err != nil {
			return nil, err
		}
	}
	if c.Intro != "" {
		if err := l.paragraph(c.Intro, marginLeft, false, 10, cText, 6, false); err != nil {
			return nil, err
		}
	}
	for _, s := range c.Sections {
		if err := l.paragraph(s.Heading, marginLeft, true, 11, cHeading, 14, true); err != nil {
			return nil, err
		}
		for i, f := range s.Fields {
			sb := 2.0
			if i == 0 {
				sb = 4
			}
			if err := l.row(f.Label, f.Value, 110, 10, sb); err != nil {
				return nil, err
			}
		}
		for _, b := range s.Blocks {
			if err := l.paragraph(b.Text, marginLeft, len(b.Items) > 0, 10, cText, 6, len(b.Items) > 0); err != nil {
				return nil, err
			}
			for _, it := range b.Items {
				if err := l.paragraph(it, marginLeft+18, false, 10, cText, 1.5, false); err != nil {
					return nil, err
				}
			}
		}
	}
	l.rule(14)
	if err := l.paragraph(c.ConsentHeading, marginLeft, true, 11, cHeading, 6, true); err != nil {
		return nil, err
	}
	if c.ConsentInstruction != "" {
		if err := l.paragraph(c.ConsentInstruction, marginLeft, false, 10, cText, 4, true); err != nil {
			return nil, err
		}
	}
	for _, st := range c.ConsentStatements {
		bw, err := l.width("•", false, 10)
		if err != nil {
			return nil, err
		}
		start := len(l.lines)
		if err := l.paragraph(st, marginLeft+14, false, 10, cText, 5, false); err != nil {
			return nil, err
		}
		first := &l.lines[start]
		first.runs = append([]run{{x: marginLeft + 14 - bw - 5, text: "•", size: 10, color: cText}}, first.runs...)
	}
	if len(l.glyphMu) > 0 {
		return nil, fmt.Errorf("%w: karakter tidak tersedia pada font PDF (U+%04X)", legaldoc.ErrInvalidContent, l.glyphMu[0])
	}

	top := contentTop
	if m.Draft {
		top = draftTop
	}
	var pages [][]placed
	var cur []placed
	y := top
	for i := 0; i < len(l.lines); i++ {
		ln := l.lines[i]
		sb := ln.spaceBefore
		if len(cur) == 0 {
			sb = 0
		}
		need := sb + ln.height
		j := i
		for j < len(l.lines)-1 && l.lines[j].keepWithNext {
			j++
			need += l.lines[j].spaceBefore + l.lines[j].height
		}
		if y+need > contentBot && len(cur) > 0 && need <= contentBot-top {
			pages = append(pages, cur)
			cur = nil
			y = top
			sb = 0
		} else if y+sb+ln.height > contentBot && len(cur) > 0 {
			pages = append(pages, cur)
			cur = nil
			y = top
			sb = 0
		}
		y += sb
		cur = append(cur, placed{line: ln, y: y})
		y += ln.height
	}
	if len(cur) > 0 {
		pages = append(pages, cur)
	}
	total := len(pages)

	logo, err := gopdf.ImageHolderByBytes(bankLogo)
	if err != nil {
		return nil, fmt.Errorf("logo: %w", err)
	}
	res := &Result{Pages: total}
	for p, items := range pages {
		pdf.AddPage()
		if err := drawHeader(pdf, logo, m); err != nil {
			return nil, err
		}
		for _, it := range items {
			if it.line.rule {
				pdf.SetStrokeColor(cRule.r, cRule.g, cRule.b)
				pdf.SetLineWidth(0.6)
				pdf.Line(marginLeft, it.y+it.line.height/2, pageW-marginRight, it.y+it.line.height/2)
				continue
			}
			for _, r := range it.line.runs {
				if r.text == "" {
					continue
				}
				if err := l.setFont(r.bold, r.size); err != nil {
					return nil, err
				}
				pdf.SetTextColor(r.color.r, r.color.g, r.color.b)
				pdf.SetXY(r.x, it.y)
				if err := pdf.Cell(nil, r.text); err != nil {
					return nil, err
				}
				res.Text = append(res.Text, r.text)
			}
		}
		if err := drawFooter(l, m, p+1, total); err != nil {
			return nil, err
		}
	}
	if len(l.glyphMu) > 0 {
		return nil, fmt.Errorf("%w: karakter tidak tersedia pada font PDF (U+%04X)", legaldoc.ErrInvalidContent, l.glyphMu[0])
	}
	out, err := pdf.GetBytesPdfReturnErr()
	if err != nil {
		return nil, err
	}
	res.PDF = out
	return res, nil
}

type placed struct {
	line line
	y    float64
}

func drawHeader(pdf *gopdf.GoPdf, logo gopdf.ImageHolder, m Meta) error {
	h := 34.0
	w := h * 494.0 / 197.0
	if err := pdf.ImageByHolder(logo, marginLeft, 26, &gopdf.Rect{W: w, H: h}); err != nil {
		return fmt.Errorf("logo: %w", err)
	}
	right := pageW - marginRight
	if err := pdf.SetFont("noto-bold", "", 10); err != nil {
		return err
	}
	pdf.SetTextColor(cBrand.r, cBrand.g, cBrand.b)
	if err := rightText(pdf, BankNameUpper, right, 32); err != nil {
		return err
	}
	if err := pdf.SetFont("noto", "", 8); err != nil {
		return err
	}
	pdf.SetTextColor(cMuted.r, cMuted.g, cMuted.b)
	if err := rightText(pdf, DocumentShort, right, 46); err != nil {
		return err
	}
	pdf.SetStrokeColor(cBrand.r, cBrand.g, cBrand.b)
	pdf.SetLineWidth(1.2)
	pdf.Line(marginLeft, 70, right, 70)
	if m.Draft {
		if err := pdf.SetFont("noto-bold", "", 9); err != nil {
			return err
		}
		pdf.SetTextColor(cDraft.r, cDraft.g, cDraft.b)
		txt := "DRAF - BELUM DITERBITKAN - BUKAN DOKUMEN YANG BERLAKU"
		tw, err := pdf.MeasureTextWidth(txt)
		if err != nil {
			return err
		}
		pdf.SetXY((pageW-tw)/2, 78)
		if err := pdf.Cell(nil, txt); err != nil {
			return err
		}
	}
	return nil
}

func drawFooter(l *layout, m Meta, page, total int) error {
	pdf := l.pdf
	y := pageH - 48
	pdf.SetStrokeColor(cRule.r, cRule.g, cRule.b)
	pdf.SetLineWidth(0.6)
	pdf.Line(marginLeft, y, pageW-marginRight, y)
	if err := pdf.SetFont("noto", "", 7.5); err != nil {
		return err
	}
	pdf.SetTextColor(cMuted.r, cMuted.g, cMuted.b)
	left := fmt.Sprintf("%s - %s - Versi %d", BankName, DocumentShort, m.VersionNumber)
	if m.Draft {
		left += " (DRAF)"
	}
	pdf.SetXY(marginLeft, y+6)
	if err := pdf.Cell(nil, left); err != nil {
		return err
	}
	return rightText(pdf, fmt.Sprintf("Halaman %d dari %d", page, total), pageW-marginRight, y+6)
}

func rightText(pdf *gopdf.GoPdf, s string, right, y float64) error {
	w, err := pdf.MeasureTextWidth(s)
	if err != nil {
		return err
	}
	pdf.SetXY(right-w, y)
	return pdf.Cell(nil, s)
}
