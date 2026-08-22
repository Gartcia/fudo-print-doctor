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
  'recibido', 'timestamp', 'caseId', 'clientId', 'host',
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
    hoja.appendRow(COLUMNAS);
    hoja.setFrozenRows(1);
    hoja.getRange(1, 1, 1, COLUMNAS.length).setFontWeight('bold');
  }
  return hoja;
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

  return [
    new Date(), d.timestamp || '', d.caseId || '', d.clientId || '', d.host || '',
    env.pais || '', env.zonaHoraria || '', so.nombre || '', so.build || '', so.arquitectura || '', env.powershell || '',
    env.chrome || '', env.edge || '', env.nativaVersion || '', env.tipoConexionPC || '',
    d.interface || '', tel.cantidadColas || 0, tel.cantidadHardware || 0, impresoras,
    usanFudo, d.status || '', d.rootCause || '', tel.category || '', d.confidence || '',
    d.resolved === true, tel.escalated === true, tel.durationMs || 0,
    (d.autoFixesApplied || []).join(' | '), d.schemaVersion || '',
    JSON.stringify(d)
  ];
}

function json_(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}
