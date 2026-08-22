/**
 * Fudo Print Doctor - receptor de telemetria
 * ------------------------------------------------------------------
 * Recibe los resultados que manda FudoPrintDoctor.ps1 y los guarda en la
 * planilla, una fila por corrida. Ademas expone un doGet para poder leer los
 * datos desde afuera (por ejemplo, para armar un reporte).
 *
 * COMO DESPLEGARLO
 *   1. Crear una planilla nueva en Google Sheets.
 *   2. Extensiones > Apps Script. Borrar lo que haya y pegar este archivo.
 *   3. Cambiar TOKEN por una clave inventada (letras y numeros, sin espacios).
 *   4. Implementar > Nueva implementacion > tipo "Aplicacion web":
 *        Ejecutar como: Yo
 *        Quien tiene acceso: Cualquier persona
 *      Copiar la URL que termina en /exec.
 *   5. En FudoPrintDoctor.ps1, poner esa URL en $script:TelemetryUrl
 *      (o pasarla con -TelemetryUrl).
 *
 * SI SE ACTUALIZA ESTE ARCHIVO
 *   Cuando cambian las columnas, la hoja existente se renombra a
 *   "corridas_hasta_<fecha>" y se crea una nueva con la cabecera correcta. Los datos
 *   viejos no se pierden y las filas nuevas nunca quedan desalineadas.
 *
 * SEGURIDAD
 *   La URL /exec es publica: cualquiera que la tenga puede escribir. Por eso doPost
 *   valida la forma del payload y doGet exige el TOKEN. Si en algun momento aparece
 *   basura en la planilla, alcanza con volver a implementar (Nueva version) para
 *   obtener una URL nueva y actualizar el archivo telemetria.url de los asesores.
 *   NO subir este archivo con el TOKEN real a un repositorio publico.
 *
 * COMO LEER LOS DATOS
 *   GET <URL>/exec?key=TOKEN            -> ultimas 100 corridas en JSON
 *   GET <URL>/exec?key=TOKEN&limit=500  -> mas filas
 *   GET <URL>/exec?key=TOKEN&formato=csv
 */

var TOKEN = 'CAMBIAR-POR-UNA-CLAVE';
var HOJA  = 'corridas';

var COLUMNAS = [
  'recibido', 'timestamp', 'pcId', 'corridaNro', 'transicion', 'causaAnterior',
  'escenarioLlegada', 'usoPrevio', 'colasSanas', 'colasConProblema', 'impresorasHistoricas',
  'caseId', 'clientId', 'host',
  'pais', 'zonaHoraria', 'so', 'soBuild', 'arquitectura', 'powershell',
  'chrome', 'edge', 'nativaVersion', 'conexionPC',
  'interfaz', 'cantidadColas', 'cantidadHardware', 'impresoras',
  'colaQueUsaFudo', 'status', 'causaRaiz', 'categoria', 'confianza',
  'resuelto', 'escalado', 'duracionMs', 'reparaciones', 'version', 'json'
];

function doPost(e) {
  try {
    var d = JSON.parse(e.postData.contents);

    // Este endpoint es publico (cualquiera con la URL puede escribir), asi que
    // descartamos lo que no tenga la forma de un resultado del motor.
    if (!esPayloadValido_(d)) {
      return json_({ ok: false, error: 'payload no reconocido' });
    }
    var hoja = obtenerHoja_();
    hoja.appendRow(armarFila_(d));
    try { actualizarResumen_(); } catch (e2) { /* el resumen no debe romper la recepcion */ }
    return json_({ ok: true });
  } catch (err) {
    return json_({ ok: false, error: String(err) });
  }
}

function esPayloadValido_(d) {
  if (!d || typeof d !== 'object') { return false; }
  if (typeof d.schemaVersion !== 'string' || !/^\d+\.\d+$/.test(d.schemaVersion)) { return false; }
  var estados = ['resolved', 'needs_escalation', 'partial_engine_error', 'engine_error'];
  if (estados.indexOf(d.status) === -1) { return false; }
  if (!d.telemetry && !d.checks) { return false; }
  return true;
}

function doGet(e) {
  var p = (e && e.parameter) ? e.parameter : {};
  if (p.key !== TOKEN) {
    return json_({ ok: false, error: 'clave invalida' });
  }

  // Dashboard como pagina: <URL>/exec?key=TOKEN&view=dash
  if (p.view === 'dash') {
    return HtmlService.createHtmlOutput(dashboardHtml_())
      .setTitle('Fudo Print Doctor - Telemetria')
      .addMetaTag('viewport', 'width=device-width, initial-scale=1');
  }

  var hoja = obtenerHoja_();
  var limite = Math.min(parseInt(p.limit || '100', 10) || 100, 5000);
  var total = hoja.getLastRow();
  if (total < 2) { return json_({ ok: true, filas: [] }); }

  var desde = Math.max(2, total - limite + 1);
  var datos = hoja.getRange(desde, 1, total - desde + 1, COLUMNAS.length).getValues();

  if (p.formato === 'csv') {
    var lineas = [COLUMNAS.join(',')];
    for (var i = 0; i < datos.length; i++) {
      lineas.push(datos[i].map(function (c) {
        var s = String(c === null || c === undefined ? '' : c).replace(/"/g, '""');
        return '"' + s + '"';
      }).join(','));
    }
    return ContentService.createTextOutput(lineas.join('\n')).setMimeType(ContentService.MimeType.CSV);
  }

  var filas = datos.map(function (r) {
    var o = {};
    for (var i = 0; i < COLUMNAS.length; i++) { o[COLUMNAS[i]] = r[i]; }
    delete o.json;   // el JSON completo solo se guarda, no se devuelve por defecto
    return o;
  });
  return json_({ ok: true, cantidad: filas.length, filas: filas });
}

function obtenerHoja_() {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var hoja = ss.getSheetByName(HOJA);
  if (!hoja) { hoja = ss.insertSheet(HOJA); }

  if (hoja.getLastRow() === 0) {
    escribirCabecera_(hoja);
    return hoja;
  }

  // Si el motor agrego columnas, la cabecera vieja quedaria desalineada con las filas nuevas.
  // En ese caso la hoja actual se archiva y se arranca una limpia con la cabecera correcta.
  var actual = hoja.getRange(1, 1, 1, hoja.getLastColumn()).getValues()[0];
  if (actual.join('|') !== COLUMNAS.join('|')) {
    var sello = Utilities.formatDate(new Date(), Session.getScriptTimeZone(), 'yyyyMMdd-HHmm');
    hoja.setName(HOJA + '_hasta_' + sello);
    hoja = ss.insertSheet(HOJA);
    escribirCabecera_(hoja);
  }
  return hoja;
}

function escribirCabecera_(hoja) {
  hoja.appendRow(COLUMNAS);
  hoja.setFrozenRows(1);
  hoja.getRange(1, 1, 1, COLUMNAS.length).setFontWeight('bold');
}

function armarFila_(d) {
  var env = d.telemetry && d.telemetry.entorno ? d.telemetry.entorno : (d.entorno || {});
  var so  = env.so || {};
  var tel = d.telemetry || {};

  var impresoras = (tel.impresoras || []).map(function (i) {
    return i.nombre + ' [' + (i.puerto || '-') + '] ' + (i.estado || '') +
           (i.trabajos ? ' (' + i.trabajos + ' trabajos)' : '');
  }).join(' | ');

  var usanFudo = (tel.historialFudo || []).filter(function (h) { return h.deFudo > 0; })
    .map(function (h) { return h.impresora + ' (' + h.deFudo + ')'; }).join(' | ');

  var cor = d.corrida || {};
  var lle = d.llegada || {};

  return [
    new Date(), d.timestamp || '',
    d.pcId || '', cor.numero || 0, cor.transicion || '', cor.causaAnterior || '',
    lle.escenario || '', lle.usoPrevio || '', lle.colasSanas || 0, lle.colasConProblema || 0,
    lle.impresorasHistoricas || 0,
    d.caseId || '', d.clientId || '', d.host || '',
    env.pais || '', env.zonaHoraria || '', so.nombre || '', so.build || '', so.arquitectura || '', env.powershell || '',
    env.chrome || '', env.edge || '', env.nativaVersion || '', env.tipoConexionPC || '',
    d.interface || '', tel.cantidadColas || 0, tel.cantidadHardware || 0, impresoras,
    usanFudo, d.status || '', d.rootCause || '', tel.category || '', d.confidence || '',
    d.resolved === true, tel.escalated === true, tel.durationMs || 0,
    (d.autoFixesApplied || []).join(' | '), d.schemaVersion || '',
    JSON.stringify(d)
  ];
}

/**
 * Hoja "resumen": se recalcula en cada corrida recibida. Es el dashboard.
 */
function actualizarResumen_() {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var datos = obtenerHoja_();
  var total = datos.getLastRow();
  if (total < 2) { return; }

  var filas = datos.getRange(2, 1, total - 1, COLUMNAS.length).getValues();
  var idx = {};
  for (var i = 0; i < COLUMNAS.length; i++) { idx[COLUMNAS[i]] = i; }

  var pcs = {}, categorias = {}, chromes = {}, sos = {}, conexiones = {}, paises = {};
  var resueltas = 0, transiciones = {}, queResolvio = {}, escenarios = {}, usos = {};

  for (var f = 0; f < filas.length; f++) {
    var r = filas[f];
    var cat = r[idx['categoria']] || 'sin dato';
    categorias[cat] = (categorias[cat] || 0) + 1;
    chromes[r[idx['chrome']] || 'sin dato'] = (chromes[r[idx['chrome']] || 'sin dato'] || 0) + 1;
    sos[r[idx['so']] || 'sin dato'] = (sos[r[idx['so']] || 'sin dato'] || 0) + 1;
    conexiones[r[idx['conexionPC']] || 'sin dato'] = (conexiones[r[idx['conexionPC']] || 'sin dato'] || 0) + 1;
    paises[r[idx['pais']] || 'sin dato'] = (paises[r[idx['pais']] || 'sin dato'] || 0) + 1;
    if (r[idx['pcId']]) { pcs[r[idx['pcId']]] = true; }
    if (r[idx['resuelto']] === true || r[idx['resuelto']] === 'TRUE') { resueltas++; }

    var tr = r[idx['transicion']] || 'sin dato';
    transiciones[tr] = (transiciones[tr] || 0) + 1;

    var esc = r[idx['escenarioLlegada']] || 'sin dato';
    escenarios[esc] = (escenarios[esc] || 0) + 1;
    var uso = r[idx['usoPrevio']] || 'sin dato';
    usos[uso] = (usos[uso] || 0) + 1;

    // Que estaba fallando cuando algo paso a resuelto, y con que reparacion
    if (tr === 'se_resolvio') {
      var clave = (r[idx['causaAnterior']] || 'sin dato') + '  ==>  ' +
                  (r[idx['reparaciones']] || 'sin reparacion automatica (accion manual)');
      queResolvio[clave] = (queResolvio[clave] || 0) + 1;
    }
  }

  var hoja = ss.getSheetByName('resumen');
  if (!hoja) { hoja = ss.insertSheet('resumen'); }
  hoja.clear();

  var out = [];
  out.push(['FUDO PRINT DOCTOR - resumen', '']);
  out.push(['actualizado', new Date()]);
  out.push(['corridas', filas.length]);
  out.push(['PCs distintas', Object.keys(pcs).length]);
  out.push(['corridas resueltas', resueltas]);
  out.push(['% resueltas', filas.length ? Math.round(resueltas * 100 / filas.length) + '%' : '']);
  out.push(['', '']);
  out.push(bloque_('CAUSA (categoria)', categorias));
  var secciones = [
    ['EN QUE ESTADO LLEGAN (escenario)', escenarios],
    ['USO PREVIO DE LA IMPRESORA', usos],
    ['TRANSICIONES', transiciones],
    ['QUE RESOLVIO (causa anterior ==> reparacion)', queResolvio],
    ['SISTEMA OPERATIVO', sos],
    ['VERSION DE CHROME', chromes],
    ['CONEXION DE LA PC', conexiones],
    ['PAIS', paises]
  ];
  volcar_(hoja, out, categorias, secciones);
}

function bloque_(titulo, mapa) { return [titulo, 'cantidad']; }

function volcar_(hoja, cabecera, categorias, secciones) {
  var filas = cabecera.slice(0);
  filas = filas.concat(ordenar_(categorias));
  for (var s = 0; s < secciones.length; s++) {
    filas.push(['', '']);
    filas.push([secciones[s][0], 'cantidad']);
    filas = filas.concat(ordenar_(secciones[s][1]));
  }
  hoja.getRange(1, 1, filas.length, 2).setValues(filas);
  hoja.getRange('A1').setFontWeight('bold').setFontSize(12);
  hoja.setColumnWidth(1, 520);
  hoja.setColumnWidth(2, 90);
}

function ordenar_(mapa) {
  var arr = [];
  for (var k in mapa) { arr.push([k, mapa[k]]); }
  arr.sort(function (a, b) { return b[1] - a[1]; });
  return arr;
}

function json_(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}


/* ==================================================================
 *  DASHBOARD  ->  <URL>/exec?key=TOKEN&view=dash
 *  Se calcula en cada carga desde la hoja, asi que siempre esta al dia.
 *  Sin librerias externas: barras con divs, para que no dependa de CDNs.
 * ================================================================== */

function metricas_() {
  var hoja = obtenerHoja_();
  var total = hoja.getLastRow();
  var m = {
    corridas: 0, pcs: 0, resueltas: 0, escaladas: 0,
    escenarios: {}, usos: {}, categorias: {}, transiciones: {}, queResolvio: {},
    sos: {}, chromes: {}, conexiones: {}, paises: {}, nativas: {},
    ultimas: [], desde: '', hasta: ''
  };
  if (total < 2) { return m; }

  var filas = hoja.getRange(2, 1, total - 1, COLUMNAS.length).getValues();
  var idx = {};
  for (var i = 0; i < COLUMNAS.length; i++) { idx[COLUMNAS[i]] = i; }
  var pcs = {};

  function sumar(mapa, clave) {
    var k = (clave === '' || clave === null || clave === undefined) ? 'sin dato' : String(clave);
    mapa[k] = (mapa[k] || 0) + 1;
  }

  for (var f = 0; f < filas.length; f++) {
    var r = filas[f];
    m.corridas++;
    if (r[idx['pcId']]) { pcs[r[idx['pcId']]] = true; }
    var resuelto = (r[idx['resuelto']] === true || String(r[idx['resuelto']]).toUpperCase() === 'TRUE');
    if (resuelto) { m.resueltas++; }
    if (r[idx['escalado']] === true || String(r[idx['escalado']]).toUpperCase() === 'TRUE') { m.escaladas++; }

    sumar(m.escenarios, r[idx['escenarioLlegada']]);
    sumar(m.usos, r[idx['usoPrevio']]);
    sumar(m.categorias, r[idx['categoria']]);
    sumar(m.transiciones, r[idx['transicion']]);
    sumar(m.sos, r[idx['so']]);
    sumar(m.chromes, r[idx['chrome']]);
    sumar(m.conexiones, r[idx['conexionPC']]);
    sumar(m.paises, r[idx['pais']]);
    sumar(m.nativas, r[idx['nativaVersion']]);

    if (String(r[idx['transicion']]) === 'se_resolvio') {
      var clave = (r[idx['causaAnterior']] || 'sin dato') + '   ==>   ' +
                  (r[idx['reparaciones']] || 'sin reparacion automatica (accion manual del asesor)');
      m.queResolvio[clave] = (m.queResolvio[clave] || 0) + 1;
    }
  }

  m.pcs = Object.keys(pcs).length;
  var desde = Math.max(0, filas.length - 15);
  for (var u = filas.length - 1; u >= desde; u--) {
    var x = filas[u];
    m.ultimas.push({
      fecha: x[idx['recibido']], pc: String(x[idx['pcId']] || '').substring(0, 8),
      escenario: x[idx['escenarioLlegada']], causa: x[idx['causaRaiz']],
      categoria: x[idx['categoria']], transicion: x[idx['transicion']],
      resuelto: (x[idx['resuelto']] === true || String(x[idx['resuelto']]).toUpperCase() === 'TRUE')
    });
  }
  return m;
}

function esc_(s) {
  return String(s === null || s === undefined ? '' : s)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

function barras_(titulo, mapa, nota) {
  var arr = [];
  for (var k in mapa) { arr.push([k, mapa[k]]); }
  arr.sort(function (a, b) { return b[1] - a[1]; });
  if (!arr.length) { return ''; }
  var max = arr[0][1];
  var h = '<section class="bloque"><h2>' + esc_(titulo) + '</h2>';
  if (nota) { h += '<p class="nota">' + esc_(nota) + '</p>'; }
  h += '<div class="barras">';
  for (var i = 0; i < arr.length; i++) {
    var pct = max ? Math.round(arr[i][1] * 100 / max) : 0;
    h += '<div class="fila">' +
           '<div class="etiqueta" title="' + esc_(arr[i][0]) + '">' + esc_(arr[i][0]) + '</div>' +
           '<div class="pista"><div class="barra" style="width:' + Math.max(pct, 2) + '%"></div></div>' +
           '<div class="valor">' + arr[i][1] + '</div>' +
         '</div>';
  }
  return h + '</div></section>';
}

function dashboardHtml_() {
  var m = metricas_();
  var pctResueltas = m.corridas ? Math.round(m.resueltas * 100 / m.corridas) : 0;
  var ahora = Utilities.formatDate(new Date(), Session.getScriptTimeZone(), 'dd/MM/yyyy HH:mm');

  var tabla = '';
  for (var i = 0; i < m.ultimas.length; i++) {
    var u = m.ultimas[i];
    tabla += '<tr>' +
      '<td class="mono">' + esc_(Utilities.formatDate(new Date(u.fecha), Session.getScriptTimeZone(), 'dd/MM HH:mm')) + '</td>' +
      '<td class="mono">' + esc_(u.pc) + '</td>' +
      '<td>' + esc_(u.escenario) + '</td>' +
      '<td>' + esc_(u.categoria) + '</td>' +
      '<td>' + esc_(u.transicion) + '</td>' +
      '<td>' + (u.resuelto ? '<span class="ok">resuelto</span>' : '<span class="pend">pendiente</span>') + '</td>' +
      '<td class="causa">' + esc_(u.causa) + '</td>' +
    '</tr>';
  }

  return '' +
'<!DOCTYPE html><html lang="es"><head><meta charset="utf-8">' +
'<meta http-equiv="refresh" content="300">' +
'<style>' +
':root{color-scheme:light;' +
'--surface:#fcfcfb;--surface-2:#f4f3f0;--linea:#e3e2dd;' +
'--ink:#0b0b0b;--ink-2:#52514e;--ink-3:#84837d;' +
'--serie:#2a78d6;--serie-suave:#cde2fb;--ok:#0ca30c;}' +
'@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){' +
'--surface:#1a1a19;--surface-2:#222221;--linea:#383835;' +
'--ink:#ffffff;--ink-2:#c3c2b7;--ink-3:#8f8e86;' +
'--serie:#3987e5;--serie-suave:#184f95;--ok:#0ca30c;}}' +
'*{box-sizing:border-box}' +
'body{margin:0;padding:28px 22px 60px;background:var(--surface);color:var(--ink);' +
'font:15px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif}' +
'header{max-width:1080px;margin:0 auto 26px}' +
'h1{font-size:19px;margin:0 0 4px;letter-spacing:-.01em}' +
'.sub{color:var(--ink-3);font-size:13px}' +
'main{max-width:1080px;margin:0 auto}' +
'.kpis{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:12px;margin-bottom:30px}' +
'.kpi{background:var(--surface-2);border:1px solid var(--linea);border-radius:10px;padding:14px 16px}' +
'.kpi .n{font-size:30px;font-weight:600;letter-spacing:-.02em;line-height:1.1}' +
'.kpi .l{color:var(--ink-2);font-size:12px;margin-top:2px}' +
'.kpi .n.ok{color:var(--ok)}' +
'.bloque{margin:0 0 30px}' +
'h2{font-size:13px;text-transform:uppercase;letter-spacing:.06em;color:var(--ink-2);' +
'margin:0 0 10px;font-weight:600}' +
'.nota{color:var(--ink-3);font-size:12px;margin:-4px 0 10px}' +
'.barras{display:flex;flex-direction:column;gap:6px}' +
'.fila{display:grid;grid-template-columns:minmax(140px,38%) 1fr 46px;gap:10px;align-items:center}' +
'.etiqueta{font-size:13px;color:var(--ink);overflow:hidden;text-overflow:ellipsis;white-space:nowrap}' +
'.pista{background:var(--surface-2);border-radius:4px;height:14px;overflow:hidden}' +
'.barra{height:14px;background:var(--serie);border-radius:0 4px 4px 0}' +
'.valor{text-align:right;font-size:13px;color:var(--ink-2);font-variant-numeric:tabular-nums}' +
'.dos{display:grid;grid-template-columns:repeat(auto-fit,minmax(320px,1fr));gap:0 34px}' +
'table{width:100%;border-collapse:collapse;font-size:12.5px}' +
'th{text-align:left;color:var(--ink-3);font-weight:600;padding:6px 8px;border-bottom:1px solid var(--linea);' +
'text-transform:uppercase;font-size:11px;letter-spacing:.04em}' +
'td{padding:7px 8px;border-bottom:1px solid var(--linea);vertical-align:top}' +
'.mono{font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;color:var(--ink-2);white-space:nowrap}' +
'.causa{color:var(--ink-2);max-width:340px}' +
'.ok{color:var(--ok);font-weight:600}' +
'.pend{color:var(--ink-3)}' +
'footer{max-width:1080px;margin:34px auto 0;color:var(--ink-3);font-size:12px;' +
'border-top:1px solid var(--linea);padding-top:12px}' +
'.tabla-wrap{overflow-x:auto}' +
'</style></head><body>' +
'<header><h1>Fudo Print Doctor &middot; telemetria</h1>' +
'<div class="sub">actualizado ' + esc_(ahora) + ' &middot; se refresca solo cada 5 minutos</div></header>' +
'<main>' +
'<div class="kpis">' +
  '<div class="kpi"><div class="n">' + m.corridas + '</div><div class="l">corridas</div></div>' +
  '<div class="kpi"><div class="n">' + m.pcs + '</div><div class="l">PCs distintas</div></div>' +
  '<div class="kpi"><div class="n ok">' + pctResueltas + '%</div><div class="l">resueltas por el motor</div></div>' +
  '<div class="kpi"><div class="n">' + m.escaladas + '</div><div class="l">requirieron escalar</div></div>' +
'</div>' +
barras_('En que estado llegan', m.escenarios, 'Lo que el motor encontro al llegar a la PC.') +
barras_('Causa raiz', m.categorias) +
barras_('Que resolvio el problema', m.queResolvio, 'Solo las corridas donde el estado paso a resuelto: que fallaba antes y que se aplico.') +
barras_('Transiciones entre corridas de la misma PC', m.transiciones) +
'<div class="dos">' +
  barras_('Uso previo de la impresora', m.usos) +
  barras_('Conexion de la PC', m.conexiones) +
  barras_('Sistema operativo', m.sos) +
  barras_('Version de Chrome', m.chromes) +
  barras_('Version de la App Nativa', m.nativas) +
  barras_('Pais', m.paises) +
'</div>' +
'<section class="bloque"><h2>Ultimas corridas</h2><div class="tabla-wrap"><table>' +
'<tr><th>fecha</th><th>pc</th><th>escenario</th><th>categoria</th><th>transicion</th><th>estado</th><th>causa raiz</th></tr>' +
tabla + '</table></div></section>' +
'</main>' +
'<footer>Cada fila es una corrida de FudoPrintDoctor.ps1. Las PCs se identifican con un hash anonimo ' +
'(pcId), no con datos del comercio.</footer>' +
'</body></html>';
}
