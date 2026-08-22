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
