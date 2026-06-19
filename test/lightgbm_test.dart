import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bracelet_sync/services/lightgbm_ml_service.dart';
import 'package:bracelet_sync/services/feature_extractor.dart';

void main() {
  group('LightGBM Model Evaluator Tests', () {
    late LightGbmMlService service;

    setUpAll(() {
      service = LightGbmMlService();
      // Load the JSON directly from the assets folder using File I/O for tests
      final file = File('assets/models/lightgbm_model.json');
      expect(file.existsSync(), isTrue, reason: "Model JSON asset must exist.");
      final jsonString = file.readAsStringSync();
      final data = jsonDecode(jsonString) as Map<String, dynamic>;
      
      service.initializeWithMap(data);
      expect(service.isInitialized, isTrue);
    });

    test('Verify model feature names and length', () {
      expect(service.featureNames.length, 13);
      expect(service.featureNames.first, 'bvp_mean');
      expect(service.featureNames.last, 'acc_z_std');
    });

    test('Verify model output probabilities match Python predict_proba exactly', () {
      final List<List<double>> testInputs = [
        [
          0.49671414494514465, -0.13826429843902588, 0.6476885676383972, 
          1.5230298042297363, -0.2341533750295639, -0.23413695394992828, 
          1.5792127847671509, 0.7674347162246704, -0.4694743752479553, 
          0.5425600409507751, -0.4634176790714264, -0.4657297432422638, 
          0.241962268948555
        ],
        [
          -1.9132802486419678, -1.7249178886413574, -0.5622875094413757, 
          -1.0128310918807983, 0.31424733996391296, -0.9080240726470947, 
          -1.4123036861419678, 1.4656487703323364, -0.2257762998342514, 
          0.06752820312976837, -1.424748182296753, -0.5443827509880066, 
          0.11092258989810944
        ],
        [
          -1.1509935855865479, 0.3756980299949646, -0.6006386876106262, 
          -0.2916937470436096, -0.6017066240310669, 1.852278232574463, 
          -0.013497225008904934, -1.057710886001587, 0.8225449323654175, 
          -1.2208436727523804, 0.20886360108852386, -1.959670066833496, 
          -1.32818603515625
        ],
        [
          0.19686123728752136, 0.7384665608406067, 0.1713682860136032, 
          -0.1156482845544815, -0.3011036813259125, -1.4785219430923462, 
          -0.7198442220687866, -0.46063876152038574, 1.0571222305297852, 
          0.3436183035373688, -1.7630401849746704, 0.32408398389816284, 
          -0.38508227467536926
        ],
        [
          -0.6769220232963562, 0.6116762757301331, 1.0309995412826538, 
          0.9312801361083984, -0.8392175436019897, -0.3092123866081238, 
          0.3312634229660034, 0.9755451083183289, -0.4791742265224457, 
          -0.18565897643566132, -1.106334924697876, -1.1962065696716309, 
          0.8125258088111877
        ],
      ];

      final List<double> expectedProbabilities = [
        0.28652873983872174,
        0.8386192020272354,
        0.01813812726720719,
        0.9387591615778913,
        0.15984103994393334,
      ];

      for (int i = 0; i < testInputs.length; i++) {
        final probability = service.predict(testInputs[i]);
        // Allow tiny floating point margin (e.g. 1e-9)
        expect(probability, closeTo(expectedProbabilities[i], 1e-9),
            reason: "Prediction at index $i did not match Python prediction.");
      }
    });
   group('FeatureExtractor logic verification', () {
      test('Extract features returns non-empty list of correct dimensions', () {
        final tempHistory = List.filled(240, 36.5);
        final hrHistory = List.filled(60, 75.0);
        final accelHistory = List.filled(1920, [0.0, 0.0, 9.8]);

        final features = FeatureExtractor.extractFeatures(
          tempHistory: tempHistory,
          hrHistory: hrHistory,
          accelHistory: accelHistory,
        );

        expect(features.length, 13);
        // Verify specific elements (since temp is constant 36.5, temp_mean should be 36.5 - 35.0 = 1.5)
        expect(features[5], closeTo(1.5, 1e-5)); // temp_mean
        expect(features[6], closeTo(0.0, 1e-5)); // temp_std
        expect(features[7], closeTo(0.0, 1e-5)); // temp_slope

        // Since accel is [0, 0, 9.8], magnitude is 9.8.
        // Division by 9.8 maps it to 1.0 g.
        // Subtracting 1.0 from magMean centers it to 0.0.
        expect(features[8], closeTo(0.0, 1e-5)); // acc_mag_mean
        expect(features[9], closeTo(0.0, 1e-5)); // acc_mag_std
      });
    });
  });
}
