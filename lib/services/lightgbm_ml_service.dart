import 'dart:convert';
import 'dart:developer';
import 'dart:math' as math;
import 'package:flutter/services.dart' show rootBundle;

abstract class LightGbmNode {
  double evaluate(List<double> features);
}

class LeafNode extends LightGbmNode {
  final double leafValue;

  LeafNode(this.leafValue);

  @override
  double evaluate(List<double> features) => leafValue;
}

class SplitNode extends LightGbmNode {
  final int splitFeatureIndex;
  final double threshold;
  final LightGbmNode leftChild;
  final LightGbmNode rightChild;

  SplitNode({
    required this.splitFeatureIndex,
    required this.threshold,
    required this.leftChild,
    required this.rightChild,
  });

  @override
  double evaluate(List<double> features) {
    if (splitFeatureIndex < 0 || splitFeatureIndex >= features.length) {
      // Fallback if index out of range
      return leftChild.evaluate(features);
    }
    final val = features[splitFeatureIndex];
    if (val <= threshold) {
      return leftChild.evaluate(features);
    } else {
      return rightChild.evaluate(features);
    }
  }
}

class LightGbmMlService {
  final List<LightGbmNode> _trees = [];
  bool _isInitialized = false;
  List<String> _featureNames = [];

  bool get isInitialized => _isInitialized;
  List<String> get featureNames => List.unmodifiable(_featureNames);

  /// Loads the LightGBM JSON model and compiles decision trees in memory.
  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      final jsonString = await rootBundle.loadString('assets/models/lightgbm_model.json');
      final data = jsonDecode(jsonString) as Map<String, dynamic>;
      initializeWithMap(data);
      log("LightGbmMlService: Successfully loaded and compiled ${_trees.length} trees.");
    } catch (e) {
      log("LightGbmMlService initialization error: $e");
    }
  }

  /// Initializes the service directly using a pre-loaded map. Useful for unit testing.
  void initializeWithMap(Map<String, dynamic> data) {
    if (_isInitialized) return;
    if (data.containsKey('feature_names')) {
      _featureNames = List<String>.from(data['feature_names'] as List);
    }

    final treeInfoList = data['tree_info'] as List;
    _trees.clear();
    for (var treeData in treeInfoList) {
      final treeStructure = treeData['tree_structure'] as Map<String, dynamic>;
      _trees.add(_parseNode(treeStructure));
    }

    _isInitialized = true;
  }

  /// Evaluates the model given the 13 input features.
  /// Expects feature list in the exact order specified by featureNames:
  /// ['bvp_mean', 'bvp_std', 'bvp_mad', 'bvp_velocity_std', 'bvp_acceleration_std',
  ///  'temp_mean', 'temp_std', 'temp_slope', 'acc_mag_mean', 'acc_mag_std',
  ///  'acc_x_std', 'acc_y_std', 'acc_z_std']
  ///
  /// Returns a stress probability between 0.0 and 1.0.
  double predict(List<double> features) {
    if (!_isInitialized || _trees.isEmpty) {
      log("LightGbmMlService: Not initialized, returning default calm probability (0.0)");
      return 0.0;
    }

    double sumPrediction = 0.0;
    for (var tree in _trees) {
      sumPrediction += tree.evaluate(features);
    }

    // Apply sigmoid: 1 / (1 + exp(-x))
    final probability = 1.0 / (1.0 + math.exp(-sumPrediction));
    return probability;
  }

  LightGbmNode _parseNode(Map<String, dynamic> nodeMap) {
    if (nodeMap.containsKey('leaf_value')) {
      return LeafNode((nodeMap['leaf_value'] as num).toDouble());
    }

    final splitFeature = nodeMap['split_feature'] as int;
    final threshold = (nodeMap['threshold'] as num).toDouble();
    final leftChild = _parseNode(nodeMap['left_child'] as Map<String, dynamic>);
    final rightChild = _parseNode(nodeMap['right_child'] as Map<String, dynamic>);

    return SplitNode(
      splitFeatureIndex: splitFeature,
      threshold: threshold,
      leftChild: leftChild,
      rightChild: rightChild,
    );
  }

  /// Disposes of compiled trees.
  void dispose() {
    _trees.clear();
    _isInitialized = false;
  }
}
