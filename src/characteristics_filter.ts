import { CharacteristicWrapper, MultiWrapper } from './characteristics_base';
import { WithUUID, Characteristic } from 'homebridge';

class FilterLife extends CharacteristicWrapper {
  ctype: WithUUID<new () => Characteristic> = this.Characteristic.FilterLifeLevel;
  get = async () => {
    return 100 - (await this.system.status.getFilterUsed());
  };
}

class FilterChange extends CharacteristicWrapper {
  ctype: WithUUID<new () => Characteristic> = this.Characteristic.FilterChangeIndication;
  get = async () => {
    return (await this.system.status.getFilterUsed()) > 95 ?
      this.Characteristic.FilterChangeIndication.CHANGE_FILTER :
      this.Characteristic.FilterChangeIndication.FILTER_OK;
  };
}

export class FilterService extends MultiWrapper {
  WRAPPERS = [
    FilterLife,
    FilterChange,
  ];
}
