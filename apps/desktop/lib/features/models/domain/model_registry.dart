import 'model_catalog.dart';

class ModelRegistry {
  static final List<ModelDescriptor> recommended = [
    ModelDescriptor(
      id: 'qwen3-1_7b-q4km',
      displayName: 'Qwen 3 1.7B',
      description: 'An ultralight option for lower-memory computers.',
      source: ModelSource.huggingFace,
      repository: 'ggml-org/Qwen3-1.7B-GGUF',
      file: 'Qwen3-1.7B-Q4_K_M.gguf',
      downloadUrl: Uri.parse(
          'https://huggingface.co/ggml-org/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q4_K_M.gguf'),
      downloadSize: 1280000000,
      approximateMemoryRequirement: 2500000000,
      qualityClass: ModelQuality.fast,
      speedClass: ModelSpeed.fast,
      recommendedFor: 'Devices with at least 4 GB system memory',
      license: 'Apache-2.0',
      licenseUrl: Uri.parse('https://www.apache.org/licenses/LICENSE-2.0'),
      sha256:
          'd2387ca2dbfee2ffabce7120d3770dadca0b293052bc2f0e138fdc940d9bc7b5',
      quantization: 'Q4_K_M',
    ),
    ModelDescriptor(
      id: 'qwen3-4b-q4km',
      displayName: 'Qwen 3 4B',
      description: 'A lighter model for responsive story play.',
      source: ModelSource.huggingFace,
      repository: 'Qwen/Qwen3-4B-GGUF',
      file: 'Qwen3-4B-Q4_K_M.gguf',
      downloadUrl: Uri.parse(
          'https://huggingface.co/Qwen/Qwen3-4B-GGUF/resolve/main/Qwen3-4B-Q4_K_M.gguf'),
      downloadSize: 2500000000,
      approximateMemoryRequirement: 6000000000,
      qualityClass: ModelQuality.fast,
      speedClass: ModelSpeed.fast,
      recommendedFor: 'Devices with at least 8 GB system memory',
      license: 'Apache-2.0',
      licenseUrl: Uri.parse('https://www.apache.org/licenses/LICENSE-2.0'),
      sha256:
          '7485fe6f11af29433bc51cab58009521f205840f5b4ae3a32fa7f92e8534fdf5',
      quantization: 'Q4_K_M',
    ),
    ModelDescriptor(
      id: 'qwen3-8b-q4km',
      displayName: 'Qwen 3 8B',
      description: 'A balanced choice for richer story responses.',
      source: ModelSource.huggingFace,
      repository: 'Qwen/Qwen3-8B-GGUF',
      file: 'Qwen3-8B-Q4_K_M.gguf',
      downloadUrl: Uri.parse(
          'https://huggingface.co/Qwen/Qwen3-8B-GGUF/resolve/main/Qwen3-8B-Q4_K_M.gguf'),
      downloadSize: 5030000000,
      approximateMemoryRequirement: 10000000000,
      qualityClass: ModelQuality.balanced,
      speedClass: ModelSpeed.balanced,
      recommendedFor: 'Devices with at least 16 GB system memory',
      license: 'Apache-2.0',
      licenseUrl: Uri.parse('https://www.apache.org/licenses/LICENSE-2.0'),
      sha256:
          'd98cdcbd03e17ce47681435b5150e34c1417f50b5c0019dd560e4882c5745785',
      quantization: 'Q4_K_M',
    ),
  ];

  static List<ModelRecommendation> recommend(DeviceCapabilities device) {
    final int safeMemory = (device.systemMemoryBytes * .72).floor();
    final List<ModelDescriptor> sorted = [...recommended]..sort((a, b) => b
        .approximateMemoryRequirement
        .compareTo(a.approximateMemoryRequirement));
    return [
      for (final ModelDescriptor model in sorted)
        ModelRecommendation(
          model: model,
          fits: device.systemMemoryBytes > 0 &&
              model.approximateMemoryRequirement <= safeMemory,
        ),
    ];
  }
}
