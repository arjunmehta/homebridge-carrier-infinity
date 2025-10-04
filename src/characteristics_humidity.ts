import { CharacteristicWrapper, MultiWrapper } from './characteristics_base';
import { WithUUID, Characteristic } from 'homebridge';

class CurrentRH extends CharacteristicWrapper {
  ctype: WithUUID<new () => Characteristic> = this.Characteristic.CurrentRelativeHumidity;
  get = async () => {
    return await this.system.status.getZoneHumidity(this.context.zone);
  };
}

class TargetDehumidify extends CharacteristicWrapper {
  ctype: WithUUID<new () => Characteristic> = this.Characteristic.RelativeHumidityDehumidifierThreshold;
}

class TargetHumidify extends CharacteristicWrapper {
  ctype: WithUUID<new () => Characteristic> = this.Characteristic.RelativeHumidityHumidifierThreshold;
}


export class ThermostatRHService extends MultiWrapper {
  WRAPPERS = [
    CurrentRH,
  ];
}

export class HumidifierService extends MultiWrapper {
  WRAPPERS = [
    CurrentRH,
    TargetDehumidify,
    TargetHumidify,
  ];
}