import { Selector } from 'testcafe';
import { Helper } from './helper';


export class DesktopHelper extends Helper {
  static readonly resWidth = 1620;
  static readonly resHeight = 900;

  
  static get beforeEachDesktop(){ //změní velikost okna přihlasí se do PGadmina a vymaže řádky v databazi 
      return async (t) => {
        await t
        .resizeWindow(this.resWidth, this.resHeight)
        .typeText('.form-control', Helper.user)
        .pressKey('tab')
        .typeText(Selector('.form-control').nth(1), Helper.pass)
        .click(Selector('button').withText('Login'))
        .doubleClick(Selector('#tree span').withText('Servers'))
        .doubleClick(Selector('#tree span').withText('Databases'))
        .click(Selector('#tree span').withText('dockerdb'))
        .doubleClick(Selector('#tree span').withText('Schemas'))
        .doubleClick(Selector('#tree span').withText('Tables').nth(2))
        .click(Selector('#tree span').withText('events_raw'))
        .rightClick(Selector('#tree span').withText('events_raw'))
        .click(Selector('div').withText('Truncate').nth(1))
        .click(Selector('li').withText('Truncate Cascade').nth(1))
        .click(Selector('span').withText('Yes'));
        };
    }
    
}