import { Selector } from 'testcafe';

export class DBHelper {
  private static _oneDay = "/partial-testing/incidents-1den.csv";
  private static _oneWeek = "/partial-testing/incidents-1tyden.csv";
  private static _oneMonth = "/partial-testing/incidents-1mesic.csv";
  private static _sixMonths = "/partial-testing/incidents-6mesicu.csv";
  private static _oneYear = "/partial-testing/incidents-12mesicu.csv";

  
  static get oneDay(){
    return this._oneDay;
    }

  static get oneWeek(){
    return this._oneWeek;
    }

  static get oneMonth(){
    return this._oneMonth
  }

   static get sixMonths(){
    return this._sixMonths
  }
  
   static get oneYear(){
    return this._oneYear
  }

  
}
