// Usage: node tools/generate_reference.mjs <path-to-original-fork>
// Development-only oracle. The shipped game has no JS/Node dependency.
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { pathToFileURL, fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
const root=path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const source=path.resolve(process.argv[2]);
const ts=createRequire(path.join(source,'package.json'))('typescript');
const out=path.join(root,'tmp','reference'); fs.mkdirSync(out,{recursive:true});
fs.writeFileSync(path.join(root,'tmp','.gdignore'),'');
const visited=new Set();
function compile(relative){
  if(visited.has(relative)) return; visited.add(relative);
  const input=fs.readFileSync(path.join(source,relative),'utf8');
  let code=ts.transpileModule(input,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText;
  code=code.replace(/from\s+(['"])(\.[^'"]+)\1/g,(full,q,spec)=>{
    let dependency=path.normalize(path.join(path.dirname(relative),spec+'.ts'));
    compile(dependency);return 'from '+q+spec+'.mjs'+q;
  });
  const target=path.join(out,relative.replace(/\.ts$/,'.mjs'));fs.mkdirSync(path.dirname(target),{recursive:true});fs.writeFileSync(target,code);
}
const ruleFile='src/game/variants/shandong/shandongRules.ts';
compile(ruleFile);compile('src/game/variants/shandong/shandongAi.ts');
const rules=await import(pathToFileURL(path.join(out,ruleFile.replace('.ts','.mjs'))));
const ai=await import(pathToFileURL(path.join(out,'src/game/variants/shandong/shandongAi.mjs')));
const tileNames=[...['m','p','s'].flatMap(s=>Array.from({length:9},(_,i)=>s+(i+1))),'east','south','west','north','red','green','white',...Array.from({length:8},(_,i)=>'f'+(i+1))];
let seed=75319;const random=n=>{seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed%n;};
const samples=[];
function add(hand,melds=[],label='generated'){
  for(const luan of [false,true]){
    const handCodes=hand.map(t=>tileNames[t]);
    const meldCodes=melds.map(m=>({...m,tile:tileNames[m.tile],tiles:m.tiles.map(t=>tileNames[t])}));
    for(const state of [{},{self_draw:true,bao:true},{self_draw:true,ming:true,haidi:true},{tianhu:true},{dihu:true}]){
      const flags={luanJiang:luan,selfDraw:!!state.self_draw,isBaoTing:!!state.bao,isMingLou:!!state.ming,haidi:!!state.haidi,tianhu:!!state.tianhu,dihu:!!state.dihu};
      const evaluation=rules.evaluateShandongHand({melds:meldCodes},handCodes,meldCodes,flags);
      samples.push({label,hand,melds,flags:{...state,luan},winning:rules.isWinningHand(handCodes,meldCodes,{luanJiang:luan}),expected:evaluation?{pattern:evaluation.pattern,base:evaluation.baseMultiplier,multiplier:evaluation.totalMultiplier,hua:evaluation.huaPoints,points:evaluation.totalPoints,win_type:evaluation.winType}:null});
    }
  }
}
for(let i=0;i<90;i++){
  const hand=[]; const melds=[];
  for(let group=0;group<4;group++){
    const tile=random(34);const sequence=tile<27&&tile%9<=6&&random(2)===0;
    const tiles=sequence?[tile,tile+1,tile+2]:[tile,tile,tile];
    if(group<2&&random(3)===0){
      const kong=!sequence&&random(3)===0;
      melds.push({type:sequence?'chi':kong?(random(2)?'gang':'angang'):'peng',tile,tiles:kong?[...tiles,tile]:tiles});
    }else hand.push(...tiles);
  }
  const eye=random(34); hand.push(eye,eye);
  const counts=Array(34).fill(0); [...hand,...melds.flatMap(m=>m.tiles)].forEach(t=>counts[t]++);
  if(counts.some(n=>n>4)) continue;
  if(random(2))melds.push({type:'flower',tile:34,tiles:[34]});
  add(hand,melds);
}
for(let i=0;i<35;i++)add(Array.from({length:14},()=>random(34)),[],'nonwinning');
add([0,8,9,17,18,26,27,28,29,30,31,32,33,33],[],'orphans');
add([0,3,6,10,13,16,20,23,26,27,28,29,30,31],[],'bukao');
add([27,27,27,28,28,28,29,29,29,30,30,30,31,31],[],'feng');
add([1,1,1,4,4,4,16,16,16,19,19,19,22,22],[],'jiang');
add([1,1,1,1,4,4,4,4,10,10,10,10,22,22],[],'three-luxury');
add([0,0,3,3,6,6,9,9,12,12,15,15,18,18],[],'no258seven');
add([0,1,2,3,4,5,6,7,8,27,27,27,13,13],[],'dragon');
add([0,1,2,3,4,5,6,7,8,3,3,3,1,1],[],'pure');
add([1],Array.from({length:8},(_,i)=>({type:'flower',tile:34+i,tiles:[34+i]})),'eightflowers');
const aiCases=[];
for(let i=0;i<16;i++){
  const hand=Array.from({length:14},()=>random(34)).sort((a,b)=>a-b);
  const codes=hand.map(t=>tileNames[t]);
  for(const luan of [false,true])for(const classic of [false,true]){
    const chosen=classic?ai.chooseClassicDiscardIndex(codes,[],luan):ai.chooseBestDiscardIndex(codes,[],luan,codes);
    aiCases.push({hand,luan,classic,index:chosen.index,ready:chosen.reachesTing});
  }
}
const metadata={source_commit:execFileSync('git',['rev-parse','HEAD'],{cwd:source,encoding:'utf8'}).trim(),source_sha256:createHash('sha256').update(fs.readFileSync(path.join(source,ruleFile))).digest('hex'),generator_seed:75319};
fs.writeFileSync(path.join(root,'tests','fixtures','upstream_rules.json'),JSON.stringify({metadata,cases:samples,ai:aiCases},null,2));
console.log(`Generated ${samples.length} rule/score oracle cases and ${aiCases.length} AI comparisons.`);
