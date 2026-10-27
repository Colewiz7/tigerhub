/// Release velocity and spring settling for gestures.
library;

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/physics.dart';

// rate 0.99 pages, 0.998 scrolls free
double project(double velocity, [double rate = 0.998]) =>
    velocity / 1000 * rate / (1 - rate);

double decay(double velocity, double rate, double t) =>
    velocity * (math.pow(rate, 1000 * t) - 1) / (1000 * math.log(rate));

double rubberband(double x, double dimension, [double c = 0.55]) =>
    x.sign * (x.abs() * dimension * c) / (dimension + c * x.abs());

// faster passes close targets
double clampVelocity(double velocity, double distance, double duration) {
  final max = 2 * math.pi / duration * distance.abs();
  return velocity.sign * math.min(velocity.abs(), max);
}

const settleTolerance = Tolerance(distance: 0.5, velocity: 5);

double releaseVelocityX(DragEndDetails details) =>
    details.velocity.pixelsPerSecond.dx;

SpringSimulation settle(double from, double to, double velocity, Duration duration) {
  final seconds = duration.inMilliseconds / 1000;
  final spring = SpringDescription.withDurationAndBounce(duration: duration);
  return SpringSimulation(spring, from, to, clampVelocity(velocity, to - from, seconds), tolerance: settleTolerance);
}
