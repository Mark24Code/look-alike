package image

import (
	"fmt"
	"image"
	"image/color"
	"math"
	"os"

	"github.com/disintegration/imaging"
)

const (
	HashSize      = 8   // Hash size 8x8 = 64 bits
	ImgSize       = 32  // Preprocessing image size
	HistogramBins = 256 // Histogram bins
)

// Weights for different algorithms
var Weights = map[string]float64{
	"phash":     0.40, // Perceptual hash - insensitive to scaling and compression
	"ahash":     0.20, // Average hash - simple and fast
	"dhash":     0.20, // Difference hash - sensitive to horizontal changes
	"histogram": 0.20, // Histogram - sensitive to color distribution
}

// ImageComparator holds the computed hashes and histogram for an image
type ImageComparator struct {
	ImagePath string
	Phash     uint64
	Ahash     uint64
	Dhash     uint64
	Histogram []float64
	Width     int
	Height    int
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

	// Calculate all hashes
	if err := ic.calculatePhash(); err != nil {
		return nil, err
	}
	if err := ic.calculateAhash(); err != nil {
		return nil, err
	}
	if err := ic.calculateDhash(); err != nil {
		return nil, err
	}
	if err := ic.calculateHistogram(); err != nil {
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

// calculatePhash calculates the perceptual hash using DCT
func (ic *ImageComparator) calculatePhash() error {
	grayscale, err := resizeAndGrayscale(ic.ImagePath, ImgSize, ImgSize)
	if err != nil {
		return err
	}

	dct := dctTransform(grayscale, ImgSize)

	// Extract low frequency components
	var lowFreq []float64
	for y := 0; y < HashSize; y++ {
		for x := 0; x < HashSize; x++ {
			lowFreq = append(lowFreq, dct[y][x])
		}
	}

	// Calculate average
	var sum float64
	for _, val := range lowFreq {
		sum += val
	}
	avg := sum / float64(len(lowFreq))

	// Generate hash
	var hash uint64
	for i, val := range lowFreq {
		if val > avg {
			hash |= 1 << uint(63-i)
		}
	}

	ic.Phash = hash
	return nil
}

// calculateAhash calculates the average hash
func (ic *ImageComparator) calculateAhash() error {
	grayscale, err := resizeAndGrayscale(ic.ImagePath, ImgSize, ImgSize)
	if err != nil {
		return err
	}

	// Calculate average
	var sum float64
	for y := 0; y < ImgSize; y++ {
		for x := 0; x < ImgSize; x++ {
			sum += grayscale[y][x]
		}
	}
	avg := sum / float64(ImgSize*ImgSize)

	// Generate hash
	var hash uint64
	bitPos := 0
	for y := 0; y < ImgSize; y++ {
		for x := 0; x < ImgSize; x++ {
			if grayscale[y][x] > avg {
				// For larger hash, we need to handle more than 64 bits
				// But for compatibility with Ruby version, we store as string
				// Here we just use the first 64 bits
				if bitPos < 64 {
					hash |= 1 << uint(63-bitPos)
				}
			}
			bitPos++
		}
	}

	ic.Ahash = hash
	return nil
}

// calculateDhash calculates the difference hash
func (ic *ImageComparator) calculateDhash() error {
	// Use 9x8 image (need to compare adjacent pixels)
	grayscale, err := resizeAndGrayscale(ic.ImagePath, 9, 8)
	if err != nil {
		return err
	}

	// Compare each row's adjacent pixels
	var hash uint64
	bitPos := 0
	for y := 0; y < 8; y++ {
		for x := 0; x < 8; x++ {
			if grayscale[y][x] > grayscale[y][x+1] {
				hash |= 1 << uint(63-bitPos)
			}
			bitPos++
		}
	}

	ic.Dhash = hash
	return nil
}

// calculateHistogram calculates the grayscale histogram
func (ic *ImageComparator) calculateHistogram() error {
	img, err := loadImage(ic.ImagePath)
	if err != nil {
		return err
	}

	// Convert to grayscale
	grayImg := imaging.Grayscale(img)
	bounds := grayImg.Bounds()

	// Calculate histogram
	histogram := make([]int, HistogramBins)
	totalPixels := 0

	for y := bounds.Min.Y; y < bounds.Max.Y; y++ {
		for x := bounds.Min.X; x < bounds.Max.X; x++ {
			grayColor := grayImg.At(x, y).(color.Gray)
			histogram[grayColor.Y]++
			totalPixels++
		}
	}

	// Normalize
	ic.Histogram = make([]float64, HistogramBins)
	for i := 0; i < HistogramBins; i++ {
		ic.Histogram[i] = float64(histogram[i]) / float64(totalPixels)
	}

	return nil
}

// resizeAndGrayscale resizes and converts an image to grayscale matrix
func resizeAndGrayscale(imagePath string, width, height int) ([][]float64, error) {
	img, err := loadImage(imagePath)
	if err != nil {
		return nil, err
	}

	// Resize
	resized := imaging.Resize(img, width, height, imaging.Lanczos)
	// Convert to grayscale
	grayImg := imaging.Grayscale(resized)

	// Convert to float matrix
	bounds := grayImg.Bounds()
	grayscale := make([][]float64, height)
	for y := 0; y < height; y++ {
		grayscale[y] = make([]float64, width)
		for x := 0; x < width; x++ {
			grayColor := grayImg.At(bounds.Min.X+x, bounds.Min.Y+y).(color.Gray)
			grayscale[y][x] = float64(grayColor.Y)
		}
	}

	return grayscale, nil
}

// dctTransform performs Discrete Cosine Transform
func dctTransform(pixels [][]float64, n int) [][]float64 {
	dct := make([][]float64, n)
	for i := range dct {
		dct[i] = make([]float64, n)
	}

	for u := 0; u < n; u++ {
		for v := 0; v < n; v++ {
			sum := 0.0
			for x := 0; x < n; x++ {
				for y := 0; y < n; y++ {
					sum += pixels[y][x] *
						math.Cos((2*float64(x)+1)*float64(u)*math.Pi/(2.0*float64(n))) *
						math.Cos((2*float64(y)+1)*float64(v)*math.Pi/(2.0*float64(n)))
				}
			}

			cu := 1.0
			if u == 0 {
				cu = 1.0 / math.Sqrt(2)
			}
			cv := 1.0
			if v == 0 {
				cv = 1.0 / math.Sqrt(2)
			}
			dct[u][v] = 0.25 * cu * cv * sum
		}
	}

	return dct
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

// HistogramSimilarity calculates histogram similarity using Bhattacharyya coefficient
func HistogramSimilarity(hist1, hist2 []float64) float64 {
	if len(hist1) != len(hist2) {
		return 0.0
	}

	// Bhattacharyya coefficient
	bc := 0.0
	for i := 0; i < len(hist1); i++ {
		bc += math.Sqrt(hist1[i] * hist2[i])
	}

	return bc * 100.0 // Convert to percentage
}

// Compare compares two images and returns weighted similarity
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

// QuickCompare compares two ImageComparator instances (fast, using pre-computed hashes)
func QuickCompare(img1, img2 *ImageComparator) float64 {
	phashSim := HashSimilarity(img1.Phash, img2.Phash, 64)
	ahashSim := HashSimilarity(img1.Ahash, img2.Ahash, 1024) // 32x32 bits
	dhashSim := HashSimilarity(img1.Dhash, img2.Dhash, 64)   // 8x8 bits
	histogramSim := HistogramSimilarity(img1.Histogram, img2.Histogram)

	// Weighted average
	weightedSimilarity :=
		phashSim*Weights["phash"] +
			ahashSim*Weights["ahash"] +
			dhashSim*Weights["dhash"] +
			histogramSim*Weights["histogram"]

	return weightedSimilarity
}
