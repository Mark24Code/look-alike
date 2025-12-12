package image

import (
	"fmt"
	"image"
	_ "image/gif"
	_ "image/jpeg"
	_ "image/png"
	"math"
	"os"

	_ "github.com/chai2010/webp"
	"github.com/corona10/goimagehash"
	_ "golang.org/x/image/bmp"
	_ "golang.org/x/image/tiff"
)

const (
	HashSize      = 8   // Hash size 8x8 = 64 bits
	ImgSize       = 32  // Preprocessing image size
	HistogramBins = 256 // Histogram bins
)

// Weights for different features
var Weights = map[string]float64{
	"phash": 0.70, // Structure similarity
	"color": 0.30, // Color similarity
}

// ImageComparator holds the computed hashes and histogram for an image
type ImageComparator struct {
	ImagePath      string
	Phash          uint64
	Ahash          uint64
	Dhash          uint64
	ColorHistogram [48]float64 // RGB color histogram: R(16) + G(16) + B(16)
	Width          int
	Height         int
}

// NewImageComparator creates a new ImageComparator for the given image path
func NewImageComparator(imagePath string) (*ImageComparator, error) {
	if _, err := os.Stat(imagePath); os.IsNotExist(err) {
		return nil, fmt.Errorf("file does not exist: %s", imagePath)
	}

	// Get image dimensions
	width, height, err := getImageDimensions(imagePath)
	if err != nil {
		return nil, err
	}

	ic := &ImageComparator{
		ImagePath: imagePath,
		Width:     width,
		Height:    height,
	}

	// Calculate phash and color histogram
	if err := ic.calculatePhash(); err != nil {
		return nil, err
	}
	if err := ic.calculateColorHistogram(); err != nil {
		return nil, err
	}

	return ic, nil
}

// getImageDimensions returns the width and height of an image
func getImageDimensions(imagePath string) (int, int, error) {
	file, err := os.Open(imagePath)
	if err != nil {
		return 0, 0, err
	}
	defer file.Close()

	img, _, err := image.DecodeConfig(file)
	if err != nil {
		return 0, 0, err
	}

	return img.Width, img.Height, nil
}

// calculatePhash calculates the perceptual hash using goimagehash library
func (ic *ImageComparator) calculatePhash() error {
	img, err := loadImage(ic.ImagePath)
	if err != nil {
		return err
	}

	hash, err := goimagehash.PerceptionHash(img)
	if err != nil {
		return err
	}

	ic.Phash = hash.GetHash()
	return nil
}

// calculateColorHistogram calculates RGB color histogram
func (ic *ImageComparator) calculateColorHistogram() error {
	img, err := loadImage(ic.ImagePath)
	if err != nil {
		return err
	}

	bounds := img.Bounds()
	histogram := make([]int, 48) // R(16) + G(16) + B(16)
	totalPixels := 0

	for y := bounds.Min.Y; y < bounds.Max.Y; y++ {
		for x := bounds.Min.X; x < bounds.Max.X; x++ {
			r, g, b, _ := img.At(x, y).RGBA()
			// Convert 16-bit color values to 8-bit
			rBin := int(r>>8) / 16 // 0-15
			gBin := int(g>>8) / 16 // 0-15
			bBin := int(b>>8) / 16 // 0-15

			histogram[rBin]++      // R: 0-15
			histogram[16+gBin]++   // G: 16-31
			histogram[32+bBin]++   // B: 32-47
			totalPixels++
		}
	}

	// Normalize (divide by totalPixels * 3 because we count R, G, B separately)
	for i := 0; i < 48; i++ {
		ic.ColorHistogram[i] = float64(histogram[i]) / float64(totalPixels*3)
	}

	return nil
}

// loadImage loads an image from file
func loadImage(imagePath string) (image.Image, error) {
	file, err := os.Open(imagePath)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	img, _, err := image.Decode(file)
	if err != nil {
		return nil, err
	}

	return img, nil
}

// HammingDistance calculates the Hamming distance between two hashes
func HammingDistance(hash1, hash2 uint64) int {
	xor := hash1 ^ hash2
	distance := 0
	for xor != 0 {
		distance++
		xor &= xor - 1 // Remove the rightmost 1 bit
	}
	return distance
}

// HashSimilarity calculates hash similarity as a percentage (0-100)
func HashSimilarity(hash1, hash2 uint64, bits int) float64 {
	hammingDist := HammingDistance(hash1, hash2)
	return (1.0 - float64(hammingDist)/float64(bits)) * 100.0
}

// ColorHistogramSimilarity calculates color similarity using Bhattacharyya coefficient
func ColorHistogramSimilarity(hist1, hist2 [48]float64) float64 {
	bc := 0.0
	for i := 0; i < 48; i++ {
		bc += math.Sqrt(hist1[i] * hist2[i])
	}
	return bc * 100.0 // Convert to percentage
}

// Compare compares two images and returns similarity using perceptual hash
func Compare(imagePath1, imagePath2 string) (float64, error) {
	img1, err := NewImageComparator(imagePath1)
	if err != nil {
		return 0, err
	}

	img2, err := NewImageComparator(imagePath2)
	if err != nil {
		return 0, err
	}

	return QuickCompare(img1, img2), nil
}

// QuickCompare compares two ImageComparator instances combining structure and color
func QuickCompare(img1, img2 *ImageComparator) float64 {
	// Structure similarity (phash)
	phashSim := HashSimilarity(img1.Phash, img2.Phash, 64)

	// Color similarity (histogram)
	colorSim := ColorHistogramSimilarity(img1.ColorHistogram, img2.ColorHistogram)

	// Weighted combination
	return phashSim*Weights["phash"] + colorSim*Weights["color"]
}
