import 'dart:io';
import 'package:tflite_flutter/tflite_flutter.dart';

// ignore_for_file: avoid_print
void main() {
  final options = InterpreterOptions()..threads = 1;
  final interpreter = Interpreter.fromFile(
    File('assets/models/wesad_hardware_classifier.tflite'),
    options: options,
  );

  final inputTensors = interpreter.getInputTensors();
  for (final tensor in inputTensors) {
    print('Input  | name: ${tensor.name} | shape: ${tensor.shape} | type: ${tensor.type}');
  }

  final outputTensors = interpreter.getOutputTensors();
  for (final tensor in outputTensors) {
    print('Output | name: ${tensor.name} | shape: ${tensor.shape} | type: ${tensor.type}');
  }
  interpreter.close();
}
