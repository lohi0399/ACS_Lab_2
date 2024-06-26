// Copyright 2018 Delft University of Technology
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
#include "../utils/Timer.hpp"
#include <iostream>
#include <cmath>
#include "../baseline/imgproc.hpp"
#include "../baseline/water.hpp"
#include "../utils/Histogram.hpp"
#include "water_cuda.hpp"
#include "imgproc_cuda.hpp"
#include "imgproc_cuda.cu"


static inline void checkDimensionsEqualOrThrowErr(const Image *a, const Image *b) {
    assert(a != nullptr);
    assert(b != nullptr);
    if ((a->width != b->width) || (a->height != b->height)) {
        throw std::domain_error("Source and destination image are not of equal dimensions.");
    }
}

void performCudaConvolute(const Image *src, Image *dest, const Kernel *kernel) {
    // Check arguments
    assert((src != nullptr) && (dest != nullptr) && (kernel != nullptr));
    checkDimensionsEqualOrThrowErr(src, dest);

    unsigned char *src_img, *dest_img;
    float *kernel_weights;

    size_t source_img_size = src->height * src->width * 4 * sizeof(unsigned char);
    size_t kernel_size = kernel->height * kernel->width * sizeof(int);
    cudaMalloc(&src_img, source_img_size);
    cudaMalloc(&dest_img, source_img_size);
    cudaMalloc(&kernel_weights, kernel_size);

//   int err = cudaPeekAtLastError();
//   if (err)
//       std::cout << "ERROR at malloc:" << err << std::endl;

    size_t destination_img_size = dest->height * dest->width * 4 * sizeof(unsigned char);
    cudaMemcpy(dest_img, dest->raw.data(), destination_img_size, cudaMemcpyHostToDevice);
    cudaMemcpy(src_img, src->raw.data(), source_img_size, cudaMemcpyHostToDevice);
    cudaMemcpy(kernel_weights, kernel->weights.data(), kernel->height * kernel->width * sizeof(int),
               cudaMemcpyHostToDevice);

//   err = cudaPeekAtLastError();
//   if (err)
//       std::cout << "ERROR at memset and memcopy:" << err << std::endl;
// auto does not work here
    dim3 numthreads(32, 32, 1);
    dim3 numblocks((src->width / numthreads.x) + 1, (src->height / numthreads.y) + 1, 4);

    convolutionKernelCuda <<<numblocks, numthreads>>>(src->height, src->width,
                                                  kernel->height, kernel->width,
                                                  kernel->scale, kernel_weights,
                                                  kernel->xoff, kernel->yoff,
                                                  src_img, dest_img);

    cudaDeviceSynchronize();
//  int err = cudaPeekAtLastError();
//       std::cout << "ERROR at copying values from device" << err << std::endl;

    cudaFree(src_img);
    cudaFree(dest_img);
    cudaFree(kernel_weights);
}



std::shared_ptr<Image> runRippleStage(const Image *previous, const WaterEffectOptions *options, Timer ts) {
  // Create a new image to store the result
  auto img_rippled = std::make_shared<Image>(previous->width, previous->height);

  int numPixels = previous->height * previous->width;
  int numBlocks = (numPixels + 31) / 32;
  int blockSize = 32;
  
  int height = previous->height;
  int width = previous->width;
  // Move src image to device memory
  size_t img_size = sizeof(unsigned char) * numPixels * 4;
  unsigned char *src;
  unsigned char *dest;
  cudaMallocManaged(&src, img_size);
  cudaMallocManaged(&dest, img_size);
  cudaMemcpy((void *)src, (void *)(previous->raw.data()), img_size, cudaMemcpyHostToDevice);

  //ts.start();
  // Apply the ripple effect
  applyRippleCuda<<<numBlocks,blockSize>>>(src, dest, options->ripple_frequency,width, height);
  //ts.stop();

  //std::cout << "Stage: Ripple CUDA:        " << ts.seconds() << " s." << std::endl;

  // Transfer enhanced image from device to host memory
  cudaDeviceSynchronize();
  cudaMemcpy(img_rippled->raw.data(), (void *)dest, img_size, cudaMemcpyDeviceToHost);

  // Free device memory
  cudaFree(src);
  cudaFree(dest);
  // Save the resulting image
  if (options->save_intermediate)
    img_rippled->toPNG("output/" + options->img_name + "_rippledCUDA.png");

  return img_rippled;
}

std::shared_ptr<Image> runEnhanceStage(const Image *previous, const Histogram *hist, const WaterEffectOptions *options, Timer ts) {
  // Create a new image to store the result
  auto img_enhanced = std::make_shared<Image>(previous->width, previous->height);
  
  int numPixels = previous->height * previous->width;
  int numBlocks = (numPixels + 32 - 1) / 32;
  int blockSize = 32;

  // Move src image to device memory
  size_t img_size = sizeof(unsigned char) * numPixels * 4;
  unsigned char *src;
  cudaMallocManaged(&src, img_size);
  cudaMemcpy((void *)src, (void *)(previous->raw.data()), img_size, cudaMemcpyHostToDevice);

  //ts.start();

  // Determine the threshold from the histogram, by taking 10% of the maximum value in the histogram.
  auto max_hist = (int) (hist->max(0) * 0.1);

  unsigned char begin = 0;
  unsigned char end = 255;

  // Enhance each (non-alpha) channel of the source image
  for (int i = 0; i < 3; i++)
  {
    // Obtain the first intensity that is above the threshold.
    for (begin = 0; begin < hist->range; begin++) {
      if (hist->count(begin, i) > max_hist) {
        break;
      }
    }

    // Obtain the last intensity that is above the threshold.
    for (end = 255; end > begin; end--) {
      if (hist->count(end, i) > max_hist) {
        break;
      }
    }
    enhanceContrastLinearlyCuda<<<numBlocks, blockSize>>>(src, src, begin, end, i, numPixels);
    // Wait for completion
    cudaDeviceSynchronize();
    cudaGetLastError();
  }
  //ts.stop();

  //std::cout << "Stage: Contrast enhance CUDA:        " << ts.seconds() << " s." << std::endl;

  // Transfer enhanced image from device to host memory
  cudaMemcpy(img_enhanced->raw.data(), (void *)src, img_size, cudaMemcpyDeviceToHost);

  // Free device memory
  cudaFree(src);

  // Save the resulting image
  if (options->save_intermediate)
    img_enhanced->toPNG("output/" + options->img_name + "_enhancedCUDA.png");

  // Create and save the enhanced histogram (if enabled).
  if (options->enhance_hist) {
    auto enhanced_hist = getHistogram(img_enhanced.get());
    auto enhanced_hist_img = enhanced_hist.toImage();
    enhanced_hist_img->toPNG("output/" + options->img_name + "_enhanced_histogramCUDA.png");
  }

  return img_enhanced;
}
std::shared_ptr<Histogram> runHistogramStage(const Image *previous, const WaterEffectOptions *options, Timer ts) {
    // Histogram to hold result
    // Histogram *hist_res = new Histogram();
    auto hist_res = std::make_shared<Histogram>();

    // Determine # of threads to allocate
    int numPixels = previous->height * previous->width;
    int numBlocks = (numPixels + 32 - 1) / 32;
    int blockSize = 32;

    // Histogram stage
    
    if (options->histogram) {
   	 
	// Move src 
    size_t img_size = sizeof(unsigned char) * numPixels * 4;
    unsigned char *src;
    cudaMallocManaged(&src, img_size);
    //move to device
    cudaMemcpy((void *)src, (void *)(previous->raw.data()), img_size, cudaMemcpyHostToDevice);

    // Set up device memory for histogram
    int *hist;
    size_t hist_size = sizeof(int) * 4 * 256;
    cudaMallocManaged(&hist, hist_size);
    cudaMemset(hist, 0, hist_size);

    //ts.start();
    getHistogramCuda<<<numBlocks, blockSize>>>(src, numPixels, hist);
    // Wait for completion
    cudaDeviceSynchronize();
    //ts.stop();
    //std::cout << "Stage: Histogram CUDA:        " << ts.seconds() << " s." << std::endl;

    // Copy the result data back to host
    cudaMemcpy(hist_res->values.data(), hist, hist_size, cudaMemcpyDeviceToHost);

    if (options->save_intermediate) {
      // Copy raw data into histogram object
      auto hist_img = hist_res->toImage();
      hist_img->toPNG("output/" + options->img_name + "_histogramCUDA.png");
    }
    cudaFree(src);
    cudaFree(hist); 
  }
  return hist_res;
}

std::shared_ptr<Image> runBlurStageCUDA(const Image *previous, const WaterEffectOptions *options) {
  // Create a Gaussian convolution kernel
  Kernel gaussian = Kernel::gaussian(options->blur_size, options->blur_size, 1.0);

  // Create a new image to store the result
  auto img_blurred = std::make_shared<Image>(previous->width, previous->height);

  // Blur every channel using the gaussian kernel
  performCudaConvolute(previous, img_blurred.get(), &gaussian);

  // Save the resulting image
  if (options->save_intermediate)
    img_blurred->toPNG("output/" + options->img_name + "_blurred_cuda.png");

  return img_blurred;
}


std::shared_ptr<Image> runWaterEffectCUDA(const Image *src, const WaterEffectOptions *options) {
  /* REPLACE THIS CODE WITH YOUR OWN WATER EFFECT PIPELINE */
  Timer ts;
  // Smart pointers to intermediate images:
  std::shared_ptr<Histogram> hist;
  std::shared_ptr<Image> img_result;
  // Histogram stage
  if (options->histogram)
  {
    ts.start();
    hist = runHistogramStage(src, options, ts);
    ts.stop();
    std::cout << "Stage: Histogram CUDA:        " << ts.seconds() << " s." << std::endl;
  }
  if (options->enhance)
  {
    ts.start();
    if (hist == nullptr) {
      throw std::runtime_error("Cannot run enhance stage without histogram.");
    }
    img_result = runEnhanceStage(src, hist.get(), options, ts);
    ts.stop();
    std::cout << "Stage: Contrast enhance CUDA: " << ts.seconds() << " s." << std::endl;
  }

  // Ripple effect stage
  if (options->ripple) {
    ts.start();
    if (img_result == nullptr) {
      img_result = runRippleStage(src, options,ts);
    } else {
      img_result = runRippleStage(img_result.get(), options,ts);
    }
    ts.stop();
    std::cout << "Stage: Ripple effect CUDA:    " << ts.seconds() << " s." << std::endl;
  }

  // Gaussian blur stage
  if (options->blur) {
    ts.start();
    if (img_result == nullptr) {
      img_result = runBlurStageCUDA(src, options);
    } else {
      img_result = runBlurStageCUDA(img_result.get(), options);
    }
    ts.stop();
    std::cout << "Stage: Blur:             " << ts.seconds() << " s." << std::endl;
  }

  return nullptr;
  /* REPLACE THIS CODE WITH YOUR OWN WATER EFFECT PIPELINE */
}

