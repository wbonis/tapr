#include "CSensor.h"
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/hid/IOHIDDevice.h>
#include <mach/mach_time.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// AppleSPU's undocumented report layout is described by
// https://github.com/olvvier/apple-silicon-accelerometer .
// This implementation uses public IOKit functions with vendor-specific properties.
typedef struct {
    struct TaprSensor *owner;
    IOHIDDeviceRef device;
    int kind;
    uint8_t buffer[4096];
} Channel;
typedef struct {
    io_service_t service;
    CFTypeRef previous[3];
} Driver;
struct TaprSensor {
    TaprSampleCallback callback;
    void *context;
    Channel channels[2];
    Driver drivers[2];
    int channel_count, driver_count;
    double time_scale;
    char message[256];
};
static CFStringRef property_key(int index) {
    switch (index) {
        case 0: return CFSTR("SensorPropertyReportingState");
        case 1: return CFSTR("SensorPropertyPowerState");
        default: return CFSTR("ReportInterval");
    }
}
static int property_int(io_service_t service, CFStringRef key) {
    CFTypeRef value = IORegistryEntryCreateCFProperty(service, key, kCFAllocatorDefault, 0);
    int number = -1;
    if (value) {
        if (CFGetTypeID(value) == CFNumberGetTypeID()) CFNumberGetValue(value, kCFNumberIntType, &number);
        CFRelease(value);
    }
    return number;
}
static int motion_kind(io_service_t service) {
    if (property_int(service, CFSTR("PrimaryUsagePage")) != 0xff00) return 0;
    int usage = property_int(service, CFSTR("PrimaryUsage"));
    return usage == 3 || usage == 9 ? usage : 0;
}
static double axis(const uint8_t *bytes) {
    uint32_t raw = (uint32_t)bytes[0] | ((uint32_t)bytes[1] << 8) |
                   ((uint32_t)bytes[2] << 16) | ((uint32_t)bytes[3] << 24);
    int32_t signed_raw;
    memcpy(&signed_raw, &raw, sizeof(raw));
    return signed_raw / 65536.0;
}
static void report(void *context, IOReturn result, void *sender, IOHIDReportType type,
                   uint32_t report_id, uint8_t *bytes, CFIndex length, uint64_t timestamp) {
    Channel *channel = context;
    if (result != kIOReturnSuccess || length != 22) return;
    TaprSensor *sensor = channel->owner;
    sensor->callback(sensor->context, channel->kind, timestamp * sensor->time_scale,
                     axis(bytes + 6), axis(bytes + 10), axis(bytes + 14));
}
TaprSensor *tapr_sensor_create(TaprSampleCallback callback, void *context) {
    TaprSensor *sensor = calloc(1, sizeof(TaprSensor));
    if (!sensor) return NULL;
    sensor->callback = callback;
    sensor->context = context;
    mach_timebase_info_data_t timebase;
    mach_timebase_info(&timebase);
    sensor->time_scale = (double)timebase.numer / timebase.denom / 1e9;
    snprintf(sensor->message, sizeof(sensor->message), "Stopped");
    return sensor;
}
void tapr_sensor_stop(TaprSensor *sensor) {
    if (!sensor) return;
    for (int i = 0; i < sensor->channel_count; ++i) {
        Channel *channel = &sensor->channels[i];
        IOHIDDeviceUnscheduleFromRunLoop(channel->device, CFRunLoopGetMain(), kCFRunLoopCommonModes);
        IOHIDDeviceClose(channel->device, kIOHIDOptionsTypeNone);
        CFRelease(channel->device);
        channel->device = NULL;
    }
    sensor->channel_count = 0;
    for (int i = 0; i < sensor->driver_count; ++i) {
        Driver *driver = &sensor->drivers[i];
        for (int k = 0; k < 3; ++k) {
            // Restore only while the value still matches our request, so a later
            // client's different setting is left alone. Driver state is shared.
            int requested = k == 2 ? 1250 : 1;
            if (property_int(driver->service, property_key(k)) == requested) {
                int zero = 0;
                CFNumberRef fallback = CFNumberCreate(NULL, kCFNumberIntType, &zero);
                IORegistryEntrySetCFProperty(driver->service, property_key(k),
                                             driver->previous[k] ? driver->previous[k] : fallback);
                CFRelease(fallback);
            }
            if (driver->previous[k]) CFRelease(driver->previous[k]);
        }
        IOObjectRelease(driver->service);
    }
    sensor->driver_count = 0;
}
int tapr_sensor_start(TaprSensor *sensor) {
    tapr_sensor_stop(sensor);
    io_iterator_t iterator = 0;
    IOReturn status = IOServiceGetMatchingServices(kIOMainPortDefault,
                        IOServiceMatching("AppleSPUHIDDevice"), &iterator);
    if (status != kIOReturnSuccess) {
        snprintf(sensor->message, sizeof(sensor->message), "Cannot inspect sensors (0x%x)", status);
        return 0;
    }
    io_service_t service;
    int has_accel = 0;
    while ((service = IOIteratorNext(iterator))) {
        int kind = motion_kind(service);
        if (kind && sensor->channel_count < 2) {
            IOHIDDeviceRef device = IOHIDDeviceCreate(NULL, service);
            status = device ? IOHIDDeviceOpen(device, kIOHIDOptionsTypeNone) : kIOReturnNotPermitted;
            if (status == kIOReturnSuccess) {
                Channel *channel = &sensor->channels[sensor->channel_count++];
                channel->owner = sensor;
                channel->device = device;
                channel->kind = kind;
                IOHIDDeviceRegisterInputReportWithTimeStampCallback(device, channel->buffer,
                    sizeof(channel->buffer), report, channel);
                IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), kCFRunLoopCommonModes);
                if (kind == 3) has_accel = 1;
            } else if (device) CFRelease(device);
        }
        IOObjectRelease(service);
    }
    IOObjectRelease(iterator);
    if (!has_accel) {
        snprintf(sensor->message, sizeof(sensor->message), "Accelerometer unavailable or access denied (0x%x). Run the app outside a sandbox.", status);
        tapr_sensor_stop(sensor);
        return 0;
    }
    // Request reporting only from the two motion drivers, never unrelated SPU devices.
    status = IOServiceGetMatchingServices(kIOMainPortDefault,
                        IOServiceMatching("AppleSPUHIDDriver"), &iterator);
    int failures = 0;
    if (status == kIOReturnSuccess) {
        while ((service = IOIteratorNext(iterator))) {
            if (motion_kind(service) && sensor->driver_count < 2) {
                Driver *driver = &sensor->drivers[sensor->driver_count++];
                driver->service = service;
                for (int k = 0; k < 3; ++k) {
                    driver->previous[k] = IORegistryEntryCreateCFProperty(service, property_key(k), NULL, 0);
                    int value = k == 2 ? 1250 : 1;
                    CFNumberRef number = CFNumberCreate(NULL, kCFNumberIntType, &value);
                    if (IORegistryEntrySetCFProperty(service, property_key(k), number) != kIOReturnSuccess) failures++;
                    CFRelease(number);
                }
            } else IOObjectRelease(service);
        }
        IOObjectRelease(iterator);
    }
    snprintf(sensor->message, sizeof(sensor->message), failures ?
             "Sensor opened; some reporting requests were denied. Waiting for samples…" :
             "Sensor opened. Waiting for samples…");
    return 1;
}
void tapr_sensor_destroy(TaprSensor *sensor) {
    tapr_sensor_stop(sensor);
    free(sensor);
}
const char *tapr_sensor_message(TaprSensor *sensor) { return sensor->message; }
