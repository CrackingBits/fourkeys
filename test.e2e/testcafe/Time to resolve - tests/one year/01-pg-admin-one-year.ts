import { Selector } from 'testcafe';
import { DesktopHelper } from '../../helpers/desktop-helper'
import { DBHelper } from '../../helpers/dbhelper'
 
fixture `TIME TO RESOLVE - PGADMIN - ONE YEAR`
    .page(DesktopHelper.urlPGAdmin)
    .beforeEach(DesktopHelper.beforeEachDesktop)
    
test('Nahrání .csv pro souboru TIME TO RESOLVE - ONE YEAR ', async (t: TestController) => {
    await t
        .rightClick(Selector('#tree .icon-table').nth(1))
        .click(Selector('li').withText('Import/Export Data...'))
        .click('#c13 .MuiSvgIcon-root')
    await t
        .click('#c14')
        .pressKey('ctrl+a')
        .pressKey('backspace')
        .typeText('#c28', DBHelper.oneYear)
        
    await t
        .pressKey('tab')
        .pressKey('tab')
        .pressKey('tab')
        .pressKey('tab')
        .pressKey('tab')
        .pressKey('tab')
        .pressKey('tab')
        .pressKey('tab')
        .pressKey('enter')
        .expect(Selector('div').withText('Process completed').nth(7).visible).ok()


      
        
});



