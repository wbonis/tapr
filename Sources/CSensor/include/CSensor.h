#ifndef TAPR_SENSOR_H
#define TAPR_SENSOR_H
#include <stdint.h>

typedef struct TaprSensor TaprSensor;
// kind: 3 = acceleration in g, 9 = angular velocity in degrees/s.
typedef void (*TaprSampleCallback)(void *context, int kind, double time, double x, double y, double z);
// Call start/stop on the main thread. Callbacks use its run loop.
TaprSensor *tapr_sensor_create(TaprSampleCallback callback, void *context);
int tapr_sensor_start(TaprSensor *sensor);
void tapr_sensor_stop(TaprSensor *sensor);
void tapr_sensor_destroy(TaprSensor *sensor);
const char *tapr_sensor_message(TaprSensor *sensor);
#endif
