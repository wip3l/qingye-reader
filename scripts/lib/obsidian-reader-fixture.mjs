import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
const root = new URL('../../entry/src/main/ets/', import.meta.url);
const read = file => fs.readFileSync(new URL(file, root), 'utf8');
const compile = text => stripTypeScriptTypes(text.replace(/^import\s+[\s\S]*?\s+from\s+['"][^'"]+['"];?\r?$/gm, '')
  .replace(/\bexport /g, ''), { mode: 'transform' });

// Drawing adapter records the production painter's commands for tests and previews.
// Optional PathKit preserves native path unions in the exported review image.
export function loadObsidianReader(pathkit = null) {
  class Path {
    constructor(other) { this.d = other?.d || ''; }
    moveTo(x,y) { this.d += `M${x} ${y}`; }
    lineTo(x,y) { this.d += `L${x} ${y}`; }
    quadTo(x,y,a,b) { this.d += `Q${x} ${y} ${a} ${b}`; }
    close() { this.d += 'Z'; }
    addRoundRect(r) {
      const {left:l,top:t,right:b,bottom:d}=r.rect, v=r.radius;
      this.d+=`M${l+v} ${t}H${b-v}Q${b} ${t} ${b} ${t+v}V${d-v}Q${b} ${d} ${b-v} ${d}H${l+v}Q${l} ${d} ${l} ${d-v}V${t+v}Q${l} ${t} ${l+v} ${t}Z`;
    }
    op(other, operation) {
      if (!pathkit) { this.d += other.d; return; }
      const a=pathkit.FromSVGString(this.d),b=pathkit.FromSVGString(other.d);
      a.op(b, operation==='union'?pathkit.PathOp.UNION:pathkit.PathOp.DIFFERENCE);
      this.d=a.toSVGString();a.delete();b.delete();
    }
  }
  class Paint {
    setAntiAlias() {} setColor(c) { this.color=c; } setStrokeWidth(w) { this.width=w; }
    setJoinStyle() {} setCapStyle() {}
  }
  class Canvas {
    constructor() { this.commands=[]; }
    attachBrush(p) { this.brush=p; } detachBrush() { this.brush=null; }
    attachPen(p) { this.pen=p; } detachPen() { this.pen=null; }
    drawPath(p) { this.commands.push({d:p.d,fill:this.brush?.color,stroke:this.pen?.color,width:this.pen?.width}); }
    drawLine(x,y,a,b) { const p=new Path();p.moveTo(x,y);p.lineTo(a,b);this.drawPath(p); }
  }
  const store=new Map();
  const sandbox=vm.createContext({
    console, $r:name=>name, AppStorage:{get:key=>store.get(key),setOrCreate:(key,value)=>store.set(key,value)},
    AccountSessionStore:{hasOwnedEntitlement:()=>sandbox.granted,hasValidEntitlement:()=>false},
    drawing:{Path,Brush:Paint,Pen:Paint,PathOp:{UNION:'union',DIFFERENCE:'difference'},
      RoundRect:class {constructor(rect,radius){this.rect=rect;this.radius=radius;}},
      JoinStyle:{ROUND_JOIN:0},CapStyle:{ROUND_CAP:0}},granted:true
  });
  const modules=['utils/HexColor.ts','theme/ThemeModels.ets','theme/BuiltinThemeRegistry.ets',
    'theme/ThemeRuntime.ets','theme/ThemeAssetRegistry.ets','account/ThemeAccessPolicy.ets',
    'core/reader/ReaderFontWeight.ts','model/reader/ReaderRegexFontRule.ets','core/reader/ReaderV2Style.ets','core/reader/ReaderCommentBubble.ets'];
  const reader=read('pages/ReadBook.ets');
  const contextMethods=reader.slice(reader.indexOf('  themeRegexEmphasisMode():'),reader.indexOf('  getRegexTextSlices('));
  const templateMethod=reader.slice(reader.indexOf('  buildReaderV2RegexStyleTemplate('),reader.indexOf('  createIncrementalReaderV2Pagination('));
  vm.runInContext(modules.map(file=>compile(read(file))).join('\n')+'\n'+compile(`class ReaderHarness {
    appDarkMode=false;
    sourceSettings={};
    isReaderThemeDark(){return this.appDarkMode;}
    accentColor(){return ThemeRuntime.accentColor(this.appDarkMode);}
    getBackgroundColor(){return ThemeRuntime.currentPack()[this.appDarkMode?'dark':'light'].reader.backgroundColor;}
    getTextColor(){return ThemeRuntime.currentPack()[this.appDarkMode?'dark':'light'].reader.textColor;}
    readerSourceColorSetting(key,fallback){return this.sourceSettings[key]||fallback;}
    readerSourceSettingValue(key){return this.sourceSettings[key]||'';}
    readerV2CommentRadius(){return 4;}
    toMeasurePx(x){return x;} toMeasureFontPx(x){return x;}
    getRegexSliceFontSize(){return 21;} getRegexSliceFontFamily(){return '';}
    getRegexRuleBySlice(){return this.rule||null;}
    getStyledSliceFontColor(){return this.resolvedRegexEmphasis(this.rule||null).textColor;}
    ${contextMethods}
    ${templateMethod}
  }`)+`\nglobalThis.api={ThemeRuntime,ThemeAssetRegistry,BuiltinThemeRegistry,ReaderHarness,
    ReaderCommentBubbleStyles,ReaderCommentBubblePainter,ReaderRegexFontRule};`,sandbox);
  return {...sandbox.api,store,sandbox,Canvas};
}
