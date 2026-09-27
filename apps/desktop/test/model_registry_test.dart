import 'package:continuum_desktop/features/models/domain/model_catalog.dart';
import 'package:continuum_desktop/features/models/domain/model_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('registry contains verified, licensed recommendation artifacts', () {
    expect(ModelRegistry.recommended, hasLength(3));
    for (final ModelDescriptor model in ModelRegistry.recommended) {
      expect(model.repository, contains('/'));
      expect(model.file, endsWith('.gguf'));
      expect(model.downloadUrl.scheme, 'https');
      expect(model.sha256, hasLength(64));
      expect(model.license, 'Apache-2.0');
      expect(
          model.approximateMemoryRequirement, greaterThan(model.downloadSize));
    }
  });

  test('recommendation fit uses a conservative share of system memory', () {
    const DeviceCapabilities device = DeviceCapabilities(
      systemMemoryBytes: 16 * 1000 * 1000 * 1000,
      cpuArchitecture: 'x64',
      cpuName: 'Test CPU',
      gpuAvailable: true,
      gpuVendor: 'Test GPU',
      gpuName: 'Test Graphics',
      availableVramBytes: 8 * 1000 * 1000 * 1000,
      availableDiskBytes: 50 * 1000 * 1000 * 1000,
    );
    final List<ModelRecommendation> results = ModelRegistry.recommend(device);
    expect(results, hasLength(3));
    expect(results.first.model.id, 'qwen3-8b-q4km');
    expect(results.first.fits, isTrue);
    expect(results[1].model.id, 'qwen3-4b-q4km');
    expect(results.last.model.id, 'qwen3-1_7b-q4km');
    expect(results.last.fits, isTrue);
    const DeviceCapabilities small = DeviceCapabilities(
      systemMemoryBytes: 4 * 1000 * 1000 * 1000,
      cpuArchitecture: 'x64',
      cpuName: 'Small CPU',
      gpuAvailable: false,
      gpuVendor: null,
      gpuName: null,
      availableVramBytes: null,
      availableDiskBytes: 1,
    );
    final List<ModelRecommendation> smallDeviceResults =
        ModelRegistry.recommend(small);
    expect(smallDeviceResults.first.model.id, 'qwen3-8b-q4km');
    expect(smallDeviceResults.first.fits, isFalse);
    expect(smallDeviceResults.last.model.id, 'qwen3-1_7b-q4km');
    expect(smallDeviceResults.last.fits, isTrue);
  });
}
