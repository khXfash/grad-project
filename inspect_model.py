import tensorflow as tf

interpreter = tf.lite.Interpreter(model_path="assets/models/wesad_hardware_classifier.tflite")
interpreter.allocate_tensors()

input_details = interpreter.get_input_details()
output_details = interpreter.get_output_details()

print("Input details:")
for detail in input_details:
    print(detail)

print("\nOutput details:")
for detail in output_details:
    print(detail)
