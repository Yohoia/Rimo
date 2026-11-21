// Rimo input-only HAL driver. Custom CFData properties carry float PCM through
// CoreAudio's own IPC. The real-time reader allocates nothing and takes no locks.
#include <CoreAudio/AudioServerPlugIn.h>
#include <CoreFoundation/CFPlugInCOM.h>
#include <mach/mach_time.h>
#include <stdatomic.h>
#include <pthread.h>
#include <math.h>
#include <string.h>
#include <unistd.h>

#define DEVICE 2
#define STREAM 3
#define PCM 'spcm'
#define STATUS 'ssta'
#define UID CFSTR("cn.yohoia.rimo.microphone")
#define RATE 48000.0
#define PERIOD 16384
#define CAPACITY 131072
#define LATENCY 4800
static _Atomic uint64_t ring[CAPACITY];
static _Atomic uint32_t references = 1;
static _Atomic uint32_t running = 0;
static _Atomic uint64_t anchor = 0;
static _Atomic uint64_t lastWrite = 0;
static double ticksPerFrame;
static uint64_t currentFrame(void);
static _Atomic uint64_t writeCursor;
static _Atomic uint64_t writeCalls, readCalls, writtenFrames, readFrames, silentFrames;
// Eight UInt64 values, native endian, versioned independently of PCM transport.
static CFDataRef statusData(void) {
    uint64_t now = currentFrame();
    uint64_t end = atomic_load(&writeCursor);
    uint64_t values[] = {1, atomic_load(&running), atomic_load(&writeCalls),
        atomic_load(&readCalls), atomic_load(&writtenFrames), atomic_load(&readFrames),
        end > now ? end - now : 0, atomic_load(&silentFrames)};
    return CFDataCreate(NULL, (const UInt8 *)values, sizeof(values));
}
static pthread_mutex_t writerLock = PTHREAD_MUTEX_INITIALIZER;
static AudioServerPlugInHostRef host;
static AudioServerPlugInDriverInterface interface;
static AudioServerPlugInDriverInterface *interfacePointer = &interface;
static AudioServerPlugInDriverRef driver = &interfacePointer;

static uint64_t currentFrame(void) {
    uint64_t start = atomic_load_explicit(&anchor, memory_order_acquire);
    return ticksPerFrame > 0 ? (uint64_t)((mach_absolute_time() - start) / ticksPerFrame) : 0;
}
static AudioStreamBasicDescription format(void) {
    return (AudioStreamBasicDescription){RATE, kAudioFormatLinearPCM,
        kAudioFormatFlagsNativeFloatPacked, 4, 1, 4, 1, 32, 0};
}
static bool valid(AudioObjectID object) { return object >= 1 && object <= 3; }
static bool inputScope(AudioObjectPropertyScope scope) {
    return scope == kAudioObjectPropertyScopeGlobal || scope == kAudioObjectPropertyScopeInput;
}
static HRESULT query(void *d, REFIID uuid, LPVOID *out) {
    if (!out) return E_POINTER;
    CFUUIDRef requested = CFUUIDCreateFromUUIDBytes(NULL, uuid);
    bool matches = CFEqual(requested, IUnknownUUID) || CFEqual(requested, kAudioServerPlugInDriverInterfaceUUID);
    CFRelease(requested);
    *out = matches ? driver : NULL;
    if (matches) atomic_fetch_add(&references, 1);
    return matches ? S_OK : E_NOINTERFACE;
}
static ULONG retain(void *d) { return atomic_fetch_add(&references, 1) + 1; }
static ULONG release(void *d) {
    uint32_t old = atomic_load(&references);
    while (old > 1 && !atomic_compare_exchange_weak(&references, &old, old - 1)) {}
    return old > 1 ? old - 1 : 1;
}
static OSStatus initialize(AudioServerPlugInDriverRef d, AudioServerPlugInHostRef h) {
    host = h;
    mach_timebase_info_data_t timebase;
    mach_timebase_info(&timebase);
    ticksPerFrame = (1e9 / RATE) * timebase.denom / timebase.numer;
    atomic_store_explicit(&anchor, mach_absolute_time(), memory_order_release);
    return noErr;
}
static OSStatus create(AudioServerPlugInDriverRef d, CFDictionaryRef desc,
                       const AudioServerPlugInClientInfo *client, AudioObjectID *out) { return kAudioHardwareUnsupportedOperationError; }
static OSStatus destroy(AudioServerPlugInDriverRef d, AudioObjectID object) { return kAudioHardwareUnsupportedOperationError; }
static OSStatus client(AudioServerPlugInDriverRef d, AudioObjectID object, const AudioServerPlugInClientInfo *info) {
    return object == DEVICE ? noErr : kAudioHardwareBadObjectError;
}
static OSStatus change(AudioServerPlugInDriverRef d, AudioObjectID object, UInt64 action, void *info) {
    return object == DEVICE ? noErr : kAudioHardwareBadObjectError;
}

static OSStatus propertySize(AudioObjectID object, const AudioObjectPropertyAddress *a, UInt32 *size) {
    if (!a || !size || !valid(object)) return kAudioHardwareBadObjectError;
    if (a->mElement != kAudioObjectPropertyElementMain) return kAudioHardwareUnknownPropertyError;
    switch (a->mSelector) {
        case kAudioObjectPropertyBaseClass: case kAudioObjectPropertyClass:
        case kAudioObjectPropertyOwner: *size = sizeof(UInt32); return noErr;
        case kAudioObjectPropertyName: case kAudioObjectPropertyManufacturer:
            *size = sizeof(CFStringRef); return noErr;
        case kAudioObjectPropertyOwnedObjects:
            *size = object == 1 ? sizeof(AudioObjectID) : object == DEVICE && inputScope(a->mScope) ? sizeof(AudioObjectID) : 0;
            return noErr;
        case kAudioObjectPropertyCustomPropertyInfoList:
            if (object != DEVICE) break;
            *size = 2 * sizeof(AudioServerPlugInCustomPropertyInfo); return noErr;
        case PCM: case STATUS:
            if (object != DEVICE) break;
            *size = sizeof(CFDataRef); return noErr;
    }
    if (object == 1) switch (a->mSelector) {
        case kAudioPlugInPropertyBundleID: case kAudioPlugInPropertyResourceBundle:
            *size = sizeof(CFStringRef); return noErr;
        case kAudioPlugInPropertyDeviceList: case kAudioPlugInPropertyTranslateUIDToDevice:
            *size = sizeof(AudioObjectID); return noErr;
        case kAudioPlugInPropertyBoxList: case kAudioPlugInPropertyClockDeviceList:
            *size = 0; return noErr;
    }
    if (object == DEVICE) switch (a->mSelector) {
        case kAudioDevicePropertyDeviceUID: case kAudioDevicePropertyModelUID:
            *size = sizeof(CFStringRef); return noErr;
        case kAudioDevicePropertyTransportType: case kAudioDevicePropertyClockDomain:
        case kAudioDevicePropertyDeviceIsAlive: case kAudioDevicePropertyDeviceIsRunning:
        case kAudioDevicePropertyDeviceCanBeDefaultDevice: case kAudioDevicePropertyDeviceCanBeDefaultSystemDevice:
        case kAudioDevicePropertyLatency: case kAudioDevicePropertySafetyOffset:
        case kAudioDevicePropertyZeroTimeStampPeriod: case kAudioDevicePropertyClockIsStable:
        case kAudioDevicePropertyClockAlgorithm: case kAudioDevicePropertyIsHidden:
            *size = sizeof(UInt32); return noErr;
        case kAudioDevicePropertyStreams:
            *size = inputScope(a->mScope) ? sizeof(AudioObjectID) : 0; return noErr;
        case kAudioObjectPropertyControlList: *size = 0; return noErr;
        case kAudioDevicePropertyNominalSampleRate: *size = sizeof(Float64); return noErr;
        case kAudioDevicePropertyAvailableNominalSampleRates: *size = sizeof(AudioValueRange); return noErr;
        case kAudioDevicePropertyPreferredChannelsForStereo: *size = 2 * sizeof(UInt32); return noErr;
    }
    if (object == STREAM) switch (a->mSelector) {
        case kAudioStreamPropertyIsActive: case kAudioStreamPropertyDirection:
        case kAudioStreamPropertyTerminalType: case kAudioStreamPropertyStartingChannel:
        case kAudioStreamPropertyLatency: *size = sizeof(UInt32); return noErr;
        case kAudioStreamPropertyVirtualFormat: case kAudioStreamPropertyPhysicalFormat:
            *size = sizeof(AudioStreamBasicDescription); return noErr;
        case kAudioStreamPropertyAvailableVirtualFormats: case kAudioStreamPropertyAvailablePhysicalFormats:
            *size = sizeof(AudioStreamRangedDescription); return noErr;
    }
    return kAudioHardwareUnknownPropertyError;
}
static Boolean has(AudioServerPlugInDriverRef d, AudioObjectID object, pid_t pid, const AudioObjectPropertyAddress *a) {
    UInt32 size; return propertySize(object, a, &size) == noErr;
}
static OSStatus settable(AudioServerPlugInDriverRef d, AudioObjectID object, pid_t pid,
                         const AudioObjectPropertyAddress *a, Boolean *out) {
    UInt32 size;
    OSStatus error = propertySize(object, a, &size);
    if (error) return error;
    if (!out) return kAudioHardwareIllegalOperationError;
    *out = (object == DEVICE && (a->mSelector == PCM || a->mSelector == kAudioDevicePropertyNominalSampleRate)) ||
        (object == STREAM && (a->mSelector == kAudioStreamPropertyVirtualFormat || a->mSelector == kAudioStreamPropertyPhysicalFormat || a->mSelector == kAudioStreamPropertyIsActive));
    return noErr;
}
static OSStatus sizeOf(AudioServerPlugInDriverRef d, AudioObjectID object, pid_t pid,
                       const AudioObjectPropertyAddress *a, UInt32 qs, const void *q, UInt32 *size) {
    return propertySize(object, a, size);
}
static OSStatus get(AudioServerPlugInDriverRef d, AudioObjectID object, pid_t pid,
                    const AudioObjectPropertyAddress *a, UInt32 qs, const void *q,
                    UInt32 capacity, UInt32 *actual, void *out) {
    UInt32 size = 0;
    OSStatus error = propertySize(object, a, &size);
    if (error) return error;
    if (!actual || (size && !out)) return kAudioHardwareIllegalOperationError;
    if (capacity < size) return kAudioHardwareBadPropertySizeError;
    *actual = size;
    if (!size) return noErr;
    UInt32 value = 0;
    CFStringRef text = NULL;
    switch (a->mSelector) {
        case kAudioObjectPropertyBaseClass:
            value = object == STREAM ? kAudioObjectClassID : kAudioObjectClassID; break;
        case kAudioObjectPropertyClass:
            value = object == 1 ? kAudioPlugInClassID : object == DEVICE ? kAudioDeviceClassID : kAudioStreamClassID; break;
        case kAudioObjectPropertyOwner: value = object == 1 ? kAudioObjectUnknown : object == DEVICE ? 1 : DEVICE; break;
        case kAudioObjectPropertyName:
            text = object == 1 ? CFSTR("Rimo Audio") : object == DEVICE ? CFSTR("Rimo Remote Microphone") : CFSTR("Remote microphone input"); break;
        case kAudioObjectPropertyManufacturer: text = CFSTR("Rimo"); break;
        case kAudioObjectPropertyOwnedObjects: value = object == 1 ? DEVICE : STREAM; break;
        case kAudioObjectPropertyCustomPropertyInfoList: {
            AudioServerPlugInCustomPropertyInfo info[] = {
                {PCM, kAudioServerPlugInCustomPropertyDataTypeCFPropertyList, kAudioServerPlugInCustomPropertyDataTypeNone},
                {STATUS, kAudioServerPlugInCustomPropertyDataTypeCFPropertyList, kAudioServerPlugInCustomPropertyDataTypeNone}};
            memcpy(out, info, size); return noErr;
        }
        case STATUS: {
            CFDataRef data = statusData(); memcpy(out, &data, size); return noErr;
        }
        case PCM: {
            CFDataRef data = CFDataCreate(NULL, NULL, 0); memcpy(out, &data, size); return noErr;
        }
        case kAudioPlugInPropertyBundleID: text = CFSTR("cn.yohoia.rimo.audio"); break;
        case kAudioPlugInPropertyResourceBundle: text = CFSTR(""); break;
        case kAudioPlugInPropertyDeviceList: value = DEVICE; break;
        case kAudioPlugInPropertyTranslateUIDToDevice: {
            if (qs != sizeof(CFStringRef) || !q) return kAudioHardwareBadPropertySizeError;
            CFStringRef requested = *(CFStringRef const *)q;
            value = requested && CFEqual(requested, UID) ? DEVICE : kAudioObjectUnknown; break;
        }
        case kAudioDevicePropertyDeviceUID: text = UID; break;
        case kAudioDevicePropertyModelUID: text = CFSTR("cn.yohoia.rimo.audio.model"); break;
        case kAudioDevicePropertyTransportType: value = kAudioDeviceTransportTypeVirtual; break;
        case kAudioDevicePropertyClockDomain: value = 0; break;
        case kAudioDevicePropertyDeviceIsAlive: case kAudioDevicePropertyClockIsStable: value = 1; break;
        case kAudioDevicePropertyDeviceIsRunning: value = atomic_load(&running) > 0; break;
        case kAudioDevicePropertyDeviceCanBeDefaultDevice: value = inputScope(a->mScope); break;
        case kAudioDevicePropertyDeviceCanBeDefaultSystemDevice: value = 0; break;
        case kAudioDevicePropertyLatency: value = object == DEVICE ? LATENCY : 0; break;
        case kAudioDevicePropertySafetyOffset: case kAudioDevicePropertyIsHidden: value = 0; break;
        case kAudioDevicePropertyZeroTimeStampPeriod: value = PERIOD; break;
        case kAudioDevicePropertyClockAlgorithm: value = kAudioDeviceClockAlgorithmRaw; break;
        case kAudioDevicePropertyStreams: value = STREAM; break;
        case kAudioDevicePropertyNominalSampleRate: { Float64 rate = RATE; memcpy(out, &rate, size); return noErr; }
        case kAudioDevicePropertyAvailableNominalSampleRates: { AudioValueRange range = {RATE, RATE}; memcpy(out, &range, size); return noErr; }
        case kAudioDevicePropertyPreferredChannelsForStereo: { UInt32 channels[2] = {1, 1}; memcpy(out, channels, size); return noErr; }
        case kAudioStreamPropertyIsActive: case kAudioStreamPropertyDirection: case kAudioStreamPropertyStartingChannel: value = 1; break;
        case kAudioStreamPropertyTerminalType: value = kAudioStreamTerminalTypeMicrophone; break;
        case kAudioStreamPropertyVirtualFormat: case kAudioStreamPropertyPhysicalFormat: {
            AudioStreamBasicDescription f = format(); memcpy(out, &f, size); return noErr;
        }
        case kAudioStreamPropertyAvailableVirtualFormats: case kAudioStreamPropertyAvailablePhysicalFormats: {
            AudioStreamRangedDescription f = {format(), {RATE, RATE}}; memcpy(out, &f, size); return noErr;
        }
        default: return kAudioHardwareUnknownPropertyError;
    }
    if (text) { CFRetain(text); memcpy(out, &text, sizeof(text)); }
    else memcpy(out, &value, sizeof(value));
    return noErr;
}
static OSStatus set(AudioServerPlugInDriverRef d, AudioObjectID object, pid_t pid,
                    const AudioObjectPropertyAddress *a, UInt32 qs, const void *q,
                    UInt32 size, const void *data) {
    if (!valid(object) || !a || !data) return kAudioHardwareBadObjectError;
    Boolean allowed = false;
    OSStatus error = settable(d, object, pid, a, &allowed);
    if (error) return error;
    if (!allowed) return kAudioHardwareUnsupportedOperationError;
    if (object == DEVICE && a->mSelector == PCM) {
        if (size != sizeof(CFDataRef)) return kAudioHardwareBadPropertySizeError;
        CFDataRef bytes = *(CFDataRef const *)data;
        if (!bytes || CFGetTypeID(bytes) != CFDataGetTypeID()) return kAudioHardwareIllegalOperationError;
        CFIndex length = CFDataGetLength(bytes);
        if (length % 4 || length > 5760 * 4) return kAudioHardwareBadPropertySizeError;
        pthread_mutex_lock(&writerLock);
        uint64_t now = currentFrame();
        if (!length) {
            // Clear pending audio on a new press; old slots are never reused as
            // current audio because every slot is tagged with its sample time.
            for (size_t i = 0; i < CAPACITY; ++i) atomic_store_explicit(&ring[i], 0, memory_order_relaxed);
            writeCursor = now + LATENCY;
            atomic_store(&lastWrite, 0);
        } else {
            // Preserve queued tails across consecutive presses. Never overwrite
            // unread audio to hide an overloaded producer.
            if (writeCursor > now + RATE) {
                pthread_mutex_unlock(&writerLock);
                return kAudioHardwareIllegalOperationError;
            }
            if (writeCursor <= now) writeCursor = now + LATENCY;
            const UInt8 *source = CFDataGetBytePtr(bytes);
            for (CFIndex i = 0; i < length / 4; ++i) {
                float sample; memcpy(&sample, source + i * 4, 4);
                if (!isfinite(sample)) sample = 0;
                sample = fmaxf(-1, fminf(1, sample));
                uint32_t bits; memcpy(&bits, &sample, 4);
                uint64_t slot = ((uint64_t)(uint32_t)(writeCursor + 1) << 32) | bits;
                atomic_store_explicit(&ring[writeCursor % CAPACITY], slot, memory_order_release);
                ++writeCursor;
            }
            atomic_fetch_add(&writeCalls, 1);
            atomic_fetch_add(&writtenFrames, (uint64_t)length / 4);
            atomic_store_explicit(&lastWrite, mach_absolute_time(), memory_order_release);
        }
        pthread_mutex_unlock(&writerLock);
        return noErr;
    }
    if (a->mSelector == kAudioDevicePropertyNominalSampleRate) {
        if (size != sizeof(Float64)) return kAudioHardwareBadPropertySizeError;
        return *(const Float64 *)data == RATE ? noErr : kAudioDeviceUnsupportedFormatError;
    }
    if (a->mSelector == kAudioStreamPropertyIsActive) {
        if (size != sizeof(UInt32)) return kAudioHardwareBadPropertySizeError;
        return *(const UInt32 *)data == 1 ? noErr : kAudioHardwareUnsupportedOperationError;
    }
    if (size != sizeof(AudioStreamBasicDescription)) return kAudioHardwareBadPropertySizeError;
    AudioStreamBasicDescription expected = format();
    return memcmp(data, &expected, sizeof(expected)) == 0 ? noErr : kAudioDeviceUnsupportedFormatError;
}
static OSStatus start(AudioServerPlugInDriverRef d, AudioObjectID object, UInt32 client) {
    if (object != DEVICE) return kAudioHardwareBadObjectError;
    atomic_fetch_add(&running, 1); return noErr;
}
static OSStatus stop(AudioServerPlugInDriverRef d, AudioObjectID object, UInt32 client) {
    if (object != DEVICE) return kAudioHardwareBadObjectError;
    uint32_t old = atomic_load(&running);
    while (old && !atomic_compare_exchange_weak(&running, &old, old - 1)) {}
    return noErr;
}
static OSStatus stamp(AudioServerPlugInDriverRef d, AudioObjectID object, UInt32 client,
                      Float64 *sample, UInt64 *time, UInt64 *seed) {
    if (object != DEVICE) return kAudioHardwareBadObjectError;
    uint64_t frame = (currentFrame() / PERIOD) * PERIOD;
    *sample = frame;
    *time = atomic_load_explicit(&anchor, memory_order_acquire) + (uint64_t)(frame * ticksPerFrame);
    *seed = 1;
    return noErr;
}
static OSStatus will(AudioServerPlugInDriverRef d, AudioObjectID object, UInt32 client,
                     UInt32 operation, Boolean *yes, Boolean *inPlace) {
    if (object != DEVICE) return kAudioHardwareBadObjectError;
    *yes = operation == kAudioServerPlugInIOOperationReadInput; *inPlace = true; return noErr;
}
static OSStatus boundary(AudioServerPlugInDriverRef d, AudioObjectID object, UInt32 client,
                         UInt32 operation, UInt32 count, const AudioServerPlugInIOCycleInfo *cycle) {
    return object == DEVICE ? noErr : kAudioHardwareBadObjectError;
}
static OSStatus io(AudioServerPlugInDriverRef d, AudioObjectID object, AudioObjectID stream,
                   UInt32 client, UInt32 operation, UInt32 count,
                   const AudioServerPlugInIOCycleInfo *cycle, void *buffer, void *secondary) {
    if (object != DEVICE || stream != STREAM) return kAudioHardwareBadObjectError;
    if (operation != kAudioServerPlugInIOOperationReadInput) return noErr;
    if (!cycle || !buffer) return kAudioHardwareIllegalOperationError;
    atomic_fetch_add(&readCalls, 1);
    atomic_fetch_add(&readFrames, count);
    float *out = buffer;
    // A slot's 32-bit frame tag wraps after ~25 hours. Idle data must never
    // become audible again when a long-lived HAL process reaches that wrap.
    uint64_t last = atomic_load_explicit(&lastWrite, memory_order_acquire);
    if (!last || mach_absolute_time() - last > (uint64_t)(RATE * 2 * ticksPerFrame)) {
        atomic_fetch_add(&silentFrames, count);
        memset(out, 0, count * sizeof(float)); return noErr;
    }
    double sampleTime = cycle->mInputTime.mSampleTime;
    if (sampleTime < 0 || !isfinite(sampleTime)) { memset(out, 0, count * sizeof(float)); return noErr; }
    uint64_t first = (uint64_t)sampleTime;
    uint64_t silence = 0;
    for (UInt32 i = 0; i < count; ++i) {
        uint64_t frame = first + i;
        uint64_t slot = atomic_load_explicit(&ring[frame % CAPACITY], memory_order_acquire);
        uint32_t bits = (uint32_t)slot;
        if ((uint32_t)(slot >> 32) == (uint32_t)(frame + 1)) memcpy(out + i, &bits, 4);
        else { out[i] = 0; ++silence; }
    }
    atomic_fetch_add(&silentFrames, silence);
    return noErr;
}
static AudioServerPlugInDriverInterface interface = {
    NULL, query, retain, release, initialize, create, destroy, client, client,
    change, change, has, settable, sizeOf, get, set, start, stop, stamp, will, boundary, io, boundary
};
__attribute__((visibility("default")))
void *RimoMicrophoneFactory(CFAllocatorRef allocator, CFUUIDRef type) {
    return type && CFEqual(type, kAudioServerPlugInTypeUUID) ? driver : NULL;
}
