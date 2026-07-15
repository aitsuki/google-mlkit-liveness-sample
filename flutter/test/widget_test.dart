import 'package:flutter_test/flutter_test.dart';
import 'package:liveness/camera/face_analyzer.dart';

void main() {
  test('only continuous failures reset the flow', () {
    final controller = LivenessController()..nextStep();

    controller.onFailedDetection(1000);
    controller.onValidDetection();
    controller.onFailedDetection(4000);
    controller.onFailedDetection(5499);
    expect(controller.step, LivenessStep.smile);

    controller.onFailedDetection(5500);
    expect(controller.step, LivenessStep.front);
  });
}
