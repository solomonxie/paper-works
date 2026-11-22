/**
 * @format
 */

import { AppRegistry } from 'react-native';
import registerCallableModule from 'react-native/Libraries/Core/registerCallableModule';
import App from './App';
import { name as appName } from './app.json';

// Release builds get a legacy native event at launch that nothing registers for, which is fatal; drop it.
registerCallableModule('RCTEventEmitter', { receiveEvent() {}, receiveTouches() {} });

AppRegistry.registerComponent(appName, () => App);
