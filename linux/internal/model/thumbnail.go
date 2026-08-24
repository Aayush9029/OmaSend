package model

import (
	"bytes"
	"encoding/base64"
	"image"
	_ "image/gif"
	_ "image/jpeg"
	"image/png"
)

func ImageThumbnail(encoded string) string {
	data, err := base64.StdEncoding.DecodeString(encoded)
	if err != nil {
		return ""
	}
	source, _, err := image.Decode(bytes.NewReader(data))
	if err != nil {
		return ""
	}
	bounds := source.Bounds()
	if bounds.Dx() <= 0 || bounds.Dy() <= 0 {
		return ""
	}
	width, height := 160, 160
	if bounds.Dx() > bounds.Dy() {
		height = max(1, 160*bounds.Dy()/bounds.Dx())
	} else {
		width = max(1, 160*bounds.Dx()/bounds.Dy())
	}
	target := image.NewRGBA(image.Rect(0, 0, width, height))
	for y := 0; y < height; y++ {
		for x := 0; x < width; x++ {
			sourceX := bounds.Min.X + x*bounds.Dx()/width
			sourceY := bounds.Min.Y + y*bounds.Dy()/height
			target.Set(x, y, source.At(sourceX, sourceY))
		}
	}
	var output bytes.Buffer
	if png.Encode(&output, target) != nil {
		return ""
	}
	return base64.StdEncoding.EncodeToString(output.Bytes())
}
