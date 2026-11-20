package devicebind

import (
	"encoding/binary"
	"errors"
	"math"
)

var errCBOR = errors.New("cbor: format tidak valid")

const (
	cborMaxDepth = 8
	cborMaxItems = 1024
)

type cborDecoder struct {
	b   []byte
	pos int
}

func decodeCBOR(b []byte) (interface{}, error) {
	d := &cborDecoder{b: b}
	v, err := d.item(0)
	if err != nil {
		return nil, err
	}
	if d.pos != len(d.b) {
		return nil, errCBOR
	}
	return v, nil
}

func (d *cborDecoder) need(n uint64) error {
	if n > uint64(len(d.b)-d.pos) {
		return errCBOR
	}
	return nil
}

func (d *cborDecoder) head() (major byte, arg uint64, err error) {
	if err = d.need(1); err != nil {
		return
	}
	ib := d.b[d.pos]
	d.pos++
	major, info := ib>>5, ib&0x1f
	switch {
	case info < 24:
		arg = uint64(info)
	case info == 24:
		if err = d.need(1); err == nil {
			arg = uint64(d.b[d.pos])
			d.pos++
		}
	case info == 25:
		if err = d.need(2); err == nil {
			arg = uint64(binary.BigEndian.Uint16(d.b[d.pos:]))
			d.pos += 2
		}
	case info == 26:
		if err = d.need(4); err == nil {
			arg = uint64(binary.BigEndian.Uint32(d.b[d.pos:]))
			d.pos += 4
		}
	case info == 27:
		if err = d.need(8); err == nil {
			arg = binary.BigEndian.Uint64(d.b[d.pos:])
			d.pos += 8
		}
	default: // 28-30 reserved, 31 indefinite length
		err = errCBOR
	}
	return
}

func (d *cborDecoder) item(depth int) (interface{}, error) {
	if depth > cborMaxDepth {
		return nil, errCBOR
	}
	major, arg, err := d.head()
	if err != nil {
		return nil, err
	}
	switch major {
	case 0:
		return arg, nil
	case 1:
		if arg > math.MaxInt64 {
			return nil, errCBOR
		}
		return -1 - int64(arg), nil
	case 2, 3:
		if err := d.need(arg); err != nil {
			return nil, err
		}
		s := d.b[d.pos : d.pos+int(arg)]
		d.pos += int(arg)
		if major == 3 {
			return string(s), nil
		}
		return append([]byte(nil), s...), nil
	case 4:
		if arg > cborMaxItems {
			return nil, errCBOR
		}
		out := make([]interface{}, 0, int(arg))
		for i := uint64(0); i < arg; i++ {
			v, err := d.item(depth + 1)
			if err != nil {
				return nil, err
			}
			out = append(out, v)
		}
		return out, nil
	case 5:
		if arg > cborMaxItems {
			return nil, errCBOR
		}
		out := make(map[string]interface{}, int(arg))
		for i := uint64(0); i < arg; i++ {
			k, err := d.item(depth + 1)
			if err != nil {
				return nil, err
			}
			ks, ok := k.(string)
			if !ok {
				return nil, errCBOR // App Attest objects only use text keys
			}
			if _, dup := out[ks]; dup {
				return nil, errCBOR
			}
			v, err := d.item(depth + 1)
			if err != nil {
				return nil, err
			}
			out[ks] = v
		}
		return out, nil
	case 7:
		switch arg {
		case 20:
			return false, nil
		case 21:
			return true, nil
		case 22:
			return nil, nil
		}
	}
	return nil, errCBOR // tags (6), floats and other simple values are not expected
}
