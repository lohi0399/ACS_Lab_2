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

#pragma once

#include "../utils/Image.hpp"
#include "../utils/Kernel.hpp"
#include "../utils/Histogram.hpp"

__global__ void getHistogramCuda(const unsigned char *src, int numPixels, int *hist);
__global__ void enhanceContrastLinearlyCuda(unsigned char *src, unsigned char *dest, unsigned char first, unsigned char last, int channel, int numPixels);
__global__ void applyRippleCuda(unsigned char *src, unsigned char *dest, float frequency, int width, int height);
__global__ void convolutionKernelCuda(unsigned int height, unsigned int width,
                       int kernel_height, int kernel_width,
                       float kernel_scale, float *kernel_weights,
                       int kernel_xoff, int kernel_yoff,
                       unsigned char *source, unsigned char *dest);


/* You could use this file to declare seperate basic effects */
