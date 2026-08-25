package model

import (
	"image"
	"image/color"
	"image/jpeg"
	"image/png"
	"os"
	"path/filepath"
	"testing"
)

func TestImageFileThumbnail(t *testing.T) {
	source := image.NewRGBA(image.Rect(0, 0, 12, 8))
	source.Set(4, 3, color.RGBA{R: 255, A: 255})

	tests := []struct {
		name   string
		encode func(*os.File) error
	}{
		{name: "preview.png", encode: func(file *os.File) error { return png.Encode(file, source) }},
		{name: "preview.jpg", encode: func(file *os.File) error { return jpeg.Encode(file, source, nil) }},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			path := filepath.Join(t.TempDir(), test.name)
			file, err := os.Create(path)
			if err != nil {
				t.Fatal(err)
			}
			if err := test.encode(file); err != nil {
				file.Close()
				t.Fatal(err)
			}
			if err := file.Close(); err != nil {
				t.Fatal(err)
			}
			if thumbnail := ImageFileThumbnail(path); thumbnail == "" {
				t.Fatal("expected an image thumbnail")
			}
		})
	}
}

func TestImageFileThumbnailRejectsOtherFiles(t *testing.T) {
	path := filepath.Join(t.TempDir(), "notes.txt")
	if err := os.WriteFile(path, []byte("not an image"), 0600); err != nil {
		t.Fatal(err)
	}
	if thumbnail := ImageFileThumbnail(path); thumbnail != "" {
		t.Fatal("expected no thumbnail for a non-image file")
	}
}
