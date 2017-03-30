%-----------------------------------------------------------------------%
% The OpenSim API is a toolkit for musculoskeletal modeling and         %
% simulation. See http://opensim.stanford.edu and the NOTICE file       %
% for more information. OpenSim is developed at Stanford University     %
% and supported by the US National Institutes of Health (U54 GM072970,  %
% R24 HD065690) and by DARPA through the Warrior Web program.           %
%                                                                       %
% Copyright (c) 2017 Stanford University and the Authors                %
% Author(s): Thomas Uchida, Chris Dembia, Carmichael Ong, Nick Bianco,  %
%            Shrinidhi K. Lakshmikanth, Ajay Seth, James Dunne          %
%                                                                       %
% Licensed under the Apache License, Version 2.0 (the "License");       %
% you may not use this file except in compliance with the License.      %
% You may obtain a copy of the License at                               %
% http://www.apache.org/licenses/LICENSE-2.0.                           %
%                                                                       %
% Unless required by applicable law or agreed to in writing, software   %
% distributed under the License is distributed on an "AS IS" BASIS,     %
% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or       %
% implied. See the License for the specific language governing          %
% permissions and limitations under the License.                        %
%-----------------------------------------------------------------------%
function device = BuildDevice(varargin)

p = inputParser();

defaultDeviceType = 'active';
defaultIsPropMyo = true;
defaultControl = [0.0 1.99 2.0 3.89 3.9 4.0;
                     0.3 0.3  1.0 1.0  0.1 0.1];
defaultSpringStiffness = 1;
defaultPassivePatellaWrap = true;
defaultMaxTension = 1000;
defaultGain = 1;

addOptional(p, 'deviceType', defaultDeviceType, ...
        @(x) strcmp(x, 'active') || strcmp(x, 'passive'))
addOptional(p, 'isPropMyo', defaultIsPropMyo)
addOptional(p, 'control', defaultControl)
addOptional(p, 'springStiffness', defaultSpringStiffness)
addOptional(p, 'passivePatellaWrap', defaultPassivePatellaWrap)
addOptional(p, 'maxTension', defaultMaxTension)
addOptional(p, 'gain', defaultGain)

parse(p,varargin{:});

deviceType = p.Results.deviceType;
isPropMyo = p.Results.isPropMyo;
control = p.Results.control;
springStiffness = p.Results.springStiffness;
passivePatellaWrap = p.Results.passivePatellaWrap;
maxTension = p.Results.maxTension;
gain = p.Results.gain;

% Build a model of a device, consisting of a PathActuator, a proportional
% myoelectric controller, and two bodies.

import org.opensim.modeling.*;

% Create the device.
% This class is from the osimExampleComponents library, and acts like a
% container for the other components of the device.
device = HopperDevice();
device.setName(['device_' deviceType])

% The device's mass is distributed between two identical cuffs that attach to
% the hopper via WeldJoints (to be added below).
deviceMass = 1;
cuffA = Body(['cuffA_' deviceType], deviceMass/2., Vec3(0), Inertia(0.5));
cuffB = Body(['cuffB_' deviceType], deviceMass/2., Vec3(0), Inertia(0.5));
device.addComponent(cuffA);
device.addComponent(cuffB);

% Attach a sphere to each cuff for visualization.
sphere = Sphere(0.01);
sphere.setName('sphere');
sphere.setColor(Vec3(1, 0, 0));
cuffA.attachGeometry(sphere);
cuffB.attachGeometry(sphere.clone());

% Create a WeldJoint to anchor cuffA to the hopper.
anchorA = WeldJoint();
anchorA.setName('anchorA');
% Connect the 'child_frame' (a PhysicalFrame) Socket of anchorA to cuffA.
% Note that only the child frame is connected now; the parent frame will be
% connected in a different file (TODO).
anchorA.connectSocket_child_frame(cuffA);
device.addComponent(anchorA);

% Create a WeldJoint to anchor cuffB to the hopper. Connect the 'child_frame'
% Socket of anchorB to cuffB and add anchorB to the device.
anchorB = WeldJoint();
anchorB.setName('anchorB');
anchorB.connectSocket_child_frame(cuffB);
device.addComponent(anchorB);

switch deviceType
    case 'active'
        % Attach a PathActuator between the two cuffs.
        pathActuator = PathActuator();
        pathActuator.setName('cableAtoB');
        pathActuator.updGeometryPath().setName('geompath');
        pathActuator.setOptimalForce(maxTension);
        pathActuator.setMinControl(0.0);
        pathActuator.setMaxControl(1.0);
        pathActuator.addNewPathPoint('pointA', cuffA, Vec3(0));
        pathActuator.addNewPathPoint('pointB', cuffB, Vec3(0));
        device.addComponent(pathActuator);
        
        if isPropMyo
            % Create a proportional myoelectric controller.
            controller = ToyPropMyoController();
            controller.setName('controller');
            controller.set_gain(gain);
            % Connect the controller's 'actuator' Socket to pathActuator.
            controller.connectSocket_actuator(pathActuator);
        else
            % If not prop myo, apply user specified device control
            controller = PrescribedController();
            controller.setName('controller');
            controller.addActuator(pathActuator);
            controlFunction = PiecewiseLinearFunction();
            for i = 1:size(control,2)
                controlFunction.addPoint(control(1,i), control(2,i));
            end
            controller.addActuator(pathActuator);
            controller.prescribeControlForActuator('cableAtoB',controlFunction);
        end
        device.addComponent(controller)
        
    case 'passive'
        name = 'cableAtoB';
        springDissipation = 0.1; 
        relaxationTau = 5;
        
        if passivePatellaWrap
            spring0 = 0.7166;
        else
            spring0 = 0.6329;
        end
               
        % TODO: change ClutchedPathSpring to PathSpring
        clutchedPathSpring = ClutchedPathSpring(name, springStiffness, ...
                                  springDissipation, relaxationTau, spring0);
        clutchedPathSpring.updGeometryPath().setName('geompath');
        clutchedPathSpring.set_optimal_force(1000.0);
        clutchedPathSpring.addNewPathPoint('pointA', cuffA, Vec3(0));
        clutchedPathSpring.addNewPathPoint('pointB', cuffB, Vec3(0));
        device.addComponent(clutchedPathSpring);
        
        controller = PrescribedController();
        controller.setName('controller');
        controlFunction = PiecewiseConstantFunction();
        clutchControl = [0.0 2.5 5.0;
                         1.0 1.0 1.0];
        for i = 1:size(clutchControl,2)
            controlFunction.addPoint(clutchControl(1,i), clutchControl(2,i));
        end
        device.addComponent(controller);
end


end
