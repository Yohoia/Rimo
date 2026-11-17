// Exercise the exact plug-in implementation without installing into CoreAudio.
#include "../Rimo/AudioDriver/RimoMicrophone.c"
#include <assert.h>
#include <stdio.h>

int main(void) {
    assert(RimoMicrophoneFactory(NULL, kAudioServerPlugInTypeUUID) == driver);
    assert(initialize(driver, NULL) == noErr);
    // All advertised properties must have consistent sizes and successful getters.
    const AudioObjectPropertySelector common[] = {kAudioObjectPropertyClass, kAudioObjectPropertyBaseClass,
        kAudioObjectPropertyOwner, kAudioObjectPropertyName, kAudioObjectPropertyManufacturer, kAudioObjectPropertyOwnedObjects};
    for (AudioObjectID object = 1; object <= 3; ++object) {
        for (size_t i = 0; i < sizeof(common)/sizeof(common[0]); ++i) {
            AudioObjectPropertyAddress a = {common[i], kAudioObjectPropertyScopeGlobal, 0};
            UInt32 size = 0, actual = 0;
            assert(sizeOf(driver, object, 0, &a, 0, NULL, &size) == noErr);
            UInt8 buffer[128] = {0};
            assert(size <= sizeof(buffer));
            assert(get(driver, object, 0, &a, 0, NULL, size, &actual, buffer) == noErr);
            assert(actual == size);
            if (common[i] == kAudioObjectPropertyName || common[i] == kAudioObjectPropertyManufacturer) CFRelease(*(CFTypeRef *)buffer);
            if (size) assert(get(driver, object, 0, &a, 0, NULL, size - 1, &actual, buffer) == kAudioHardwareBadPropertySizeError);
        }
    }
    AudioObjectPropertyAddress pcm = {PCM, kAudioObjectPropertyScopeGlobal, 0};
    CFDataRef clear = CFDataCreate(NULL, NULL, 0);
    assert(set(driver, DEVICE, 0, &pcm, 0, NULL, sizeof(clear), &clear) == noErr);
    CFRelease(clear);
    float input[960];
    for (int i = 0; i < 960; ++i) input[i] = 0.5f * sinf((float)i * 0.1f);
    uint64_t first = writeCursor;
    CFDataRef data = CFDataCreate(NULL, (UInt8 *)input, sizeof(input));
    assert(set(driver, DEVICE, 0, &pcm, 0, NULL, sizeof(data), &data) == noErr);
    CFRelease(data);
    float output[960];
    AudioServerPlugInIOCycleInfo cycle = {0};
    cycle.mInputTime.mSampleTime = first;
    assert(io(driver, DEVICE, STREAM, 1, kAudioServerPlugInIOOperationReadInput, 960, &cycle, output, NULL) == noErr);
    assert(memcmp(input, output, sizeof(input)) == 0);
    // Multiple consumers must see the same samples, not drain a shared FIFO.
    memset(output, 0, sizeof(output));
    assert(io(driver, DEVICE, STREAM, 2, kAudioServerPlugInIOOperationReadInput, 960, &cycle, output, NULL) == noErr);
    assert(memcmp(input, output, sizeof(input)) == 0);
    // Unwritten frames and stale ring slots must return silence.
    cycle.mInputTime.mSampleTime = first + 960;
    assert(io(driver, DEVICE, STREAM, 1, kAudioServerPlugInIOOperationReadInput, 960, &cycle, output, NULL) == noErr);
    for (int i = 0; i < 960; ++i) assert(output[i] == 0);
    cycle.mInputTime.mSampleTime = first + CAPACITY;
    assert(io(driver, DEVICE, STREAM, 1, kAudioServerPlugInIOOperationReadInput, 960, &cycle, output, NULL) == noErr);
    for (int i = 0; i < 960; ++i) assert(output[i] == 0);
    // Reset prevents a previous session's pending audio being replayed.
    clear = CFDataCreate(NULL, NULL, 0);
    assert(set(driver, DEVICE, 0, &pcm, 0, NULL, sizeof(clear), &clear) == noErr);
    CFRelease(clear);
    cycle.mInputTime.mSampleTime = first;
    assert(io(driver, DEVICE, STREAM, 1, kAudioServerPlugInIOOperationReadInput, 960, &cycle, output, NULL) == noErr);
    for (int i = 0; i < 960; ++i) assert(output[i] == 0);
    // Bad data never reaches the real-time buffer; volume is bounded.
    UInt8 invalid[3] = {0};
    data = CFDataCreate(NULL, invalid, sizeof(invalid));
    assert(set(driver, DEVICE, 0, &pcm, 0, NULL, sizeof(data), &data) == kAudioHardwareBadPropertySizeError);
    CFRelease(data);
    float extremes[] = {NAN, INFINITY, 2.0f, -2.0f};
    first = writeCursor;
    data = CFDataCreate(NULL, (UInt8 *)extremes, sizeof(extremes));
    assert(set(driver, DEVICE, 0, &pcm, 0, NULL, sizeof(data), &data) == noErr);
    CFRelease(data);
    cycle.mInputTime.mSampleTime = first;
    assert(io(driver, DEVICE, STREAM, 1, kAudioServerPlugInIOOperationReadInput, 4, &cycle, output, NULL) == noErr);
    assert(output[0] == 0 && output[1] == 0 && output[2] == 1 && output[3] == -1);
    assert(start(driver, DEVICE, 1) == noErr && start(driver, DEVICE, 2) == noErr);
    assert(atomic_load(&running) == 2);
    assert(stop(driver, DEVICE, 1) == noErr && stop(driver, DEVICE, 2) == noErr && stop(driver, DEVICE, 2) == noErr);
    assert(atomic_load(&running) == 0);
    Float64 sample; UInt64 time, seed;
    assert(stamp(driver, DEVICE, 1, &sample, &time, &seed) == noErr && seed == 1);
    assert(fmod(sample, PERIOD) == 0 && time <= mach_absolute_time());
    puts("PASS: HAL property sizes; PCM transport; timestamped ring; multiple clients; underrun silence; reset; invalid packet rejection; bounded output; IO lifecycle; clock");
}
