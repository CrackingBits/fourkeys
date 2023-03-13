import { Selector } from 'testcafe';
import { DesktopHelper } from '../../helpers/desktop-helper'

fixture `TIME TO RESOLVE - GRAFANA - ONE WEEK`
    .page(DesktopHelper.urlGrafana);
    
test('Otestování, že v grafaně - Dashboard(FourKeys), Median Time to Restore Services je ONE WEEK ', async (t: TestController) => {
    await t
        .click(Selector('#reactRoot .css-1koed79').nth(4))
        .click(Selector('main div').withText('General').nth(7))
        .click(Selector('main a').withText('Four Keys'))
        .expect(Selector('main span').withText('One week').exists).ok()
});
