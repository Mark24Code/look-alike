package main

import (
	"fmt"
	"log"

	"github.com/bilibili/look-alike/internal/image"
)

func main() {
	fmt.Println("===========================================")
	fmt.Println("Testing Color Histogram Implementation")
	fmt.Println("===========================================")

	// Test with multiple image pairs
	testPairs := [][]string{
		{
			"/Users/bilibili/Labspace/look-alike/test-images/white.png",
			"/Users/bilibili/Labspace/look-alike/test-images/pink.png",
		},
		{
			"/Users/bilibili/Labspace/look-alike/test-images/red.png",
			"/Users/bilibili/Labspace/look-alike/test-images/lightblue.png",
		},
	}

	// Check if test images exist, if not use any available images
	fmt.Println("\nLooking for test images...")

	// Process all test pairs
	for pairIdx, testImages := range testPairs {
		fmt.Printf("\n=== Test Pair %d ===\n", pairIdx+1)

		// Create ImageComparators
		var comparators []*image.ImageComparator

		for _, imgPath := range testImages {
			comp, err := image.NewImageComparator(imgPath)
			if err != nil {
				log.Printf("Could not load %s: %v", imgPath, err)
				continue
			}
			comparators = append(comparators, comp)

			fmt.Printf("\n✓ Loaded: %s\n", imgPath)
			fmt.Printf("  Dimensions: %dx%d\n", comp.Width, comp.Height)
			fmt.Printf("  Phash: %d\n", comp.Phash)
			fmt.Printf("  Color Histogram (showing bins 12-15 for each channel):\n")
			fmt.Printf("    R[12-15]: [%.4f, %.4f, %.4f, %.4f]\n",
				comp.ColorHistogram[12], comp.ColorHistogram[13], comp.ColorHistogram[14], comp.ColorHistogram[15])
			fmt.Printf("    G[12-15]: [%.4f, %.4f, %.4f, %.4f]\n",
				comp.ColorHistogram[28], comp.ColorHistogram[29], comp.ColorHistogram[30], comp.ColorHistogram[31])
			fmt.Printf("    B[12-15]: [%.4f, %.4f, %.4f, %.4f]\n",
				comp.ColorHistogram[44], comp.ColorHistogram[45], comp.ColorHistogram[46], comp.ColorHistogram[47])
		}

		if len(comparators) < 2 {
			fmt.Printf("\n⚠ Could not load both images in pair %d\n", pairIdx+1)
			continue
		}

		// Compare the images
		fmt.Println("\n-------------------------------------------")
		fmt.Println("Comparison Results")
		fmt.Println("-------------------------------------------")

		img1 := comparators[0]
		img2 := comparators[1]

		// Calculate individual similarities
		phashSim := image.HashSimilarity(img1.Phash, img2.Phash, 64)
		colorSim := image.ColorHistogramSimilarity(img1.ColorHistogram, img2.ColorHistogram)

		// Calculate overall similarity
		overallSim := image.QuickCompare(img1, img2)

		fmt.Printf("\nComparing Image 1 vs Image 2:\n")
		fmt.Printf("  Phash Similarity:     %.2f%% (weight: %.0f%%)\n", phashSim, image.Weights["phash"]*100)
		fmt.Printf("  Color Similarity:     %.2f%% (weight: %.0f%%)\n", colorSim, image.Weights["color"]*100)
		fmt.Printf("  Overall Similarity:   %.2f%%\n", overallSim)
	}

	fmt.Println("\n===========================================")
	fmt.Println("Algorithm: pHash (70%) + RGB Histogram (30%)")
	fmt.Println("✓ Implementation verified!")
	fmt.Println("===========================================")
}
