import {
  type FaceSample,
  LivenessController,
} from '../src/liveness/LivenessController';

const frontFace: FaceSample = {
  bounds: {x: 30, y: 30, width: 40, height: 40},
  frameWidth: 100,
  frameHeight: 100,
  yawAngle: 0,
  pitchAngle: 0,
  smilingProbability: 0,
};

describe('LivenessController', () => {
  it('completes front, smile, and side after the required durations', () => {
    const controller = new LivenessController();

    expect(controller.process([frontFace], 0).captureStep).toBeUndefined();
    expect(controller.process([frontFace], 999).captureStep).toBeUndefined();
    expect(controller.process([frontFace], 1000).captureStep).toBe('front');
    expect(controller.captureSucceeded('front')).toBe('smile');

    const smile = {...frontFace, smilingProbability: 0.8};
    controller.process([smile], 2000);
    expect(controller.process([smile], 2500).captureStep).toBe('smile');
    expect(controller.captureSucceeded('smile')).toBe('side');

    const side = {...frontFace, yawAngle: 25};
    controller.process([side], 3000);
    expect(controller.process([side], 3250).captureStep).toBe('side');
    expect(controller.captureSucceeded('side')).toBe('done');
  });

  it('resets to front after failures last for 1500ms', () => {
    const controller = new LivenessController();
    controller.process([frontFace], 0);
    controller.process([frontFace], 1000);
    controller.captureSucceeded('front');

    expect(controller.process([], 1100).didReset).toBe(false);
    const result = controller.process([], 2600);
    expect(result.didReset).toBe(true);
    expect(result.step).toBe('front');
  });

  it('clears the failure window after a valid detection', () => {
    const controller = new LivenessController();

    controller.process([], 0);
    controller.process([frontFace], 1000);
    expect(controller.process([], 2000).didReset).toBe(false);
    expect(controller.process([], 3499).didReset).toBe(false);
    expect(controller.process([], 3500).didReset).toBe(true);
  });

  it.each([
    [{...frontFace, bounds: {x: 0, y: 0, width: 40, height: 40}}, 'not_center'],
    [{...frontFace, bounds: {x: 5, y: 5, width: 90, height: 90}}, 'too_close'],
    [{...frontFace, bounds: {x: 35, y: 35, width: 30, height: 30}}, 'too_far'],
  ] as const)('reports invalid front-face geometry', (face, error) => {
    const controller = new LivenessController();
    expect(controller.process([face], 0).error).toBe(error);
  });
});
