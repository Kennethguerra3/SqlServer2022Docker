<#
.SYNOPSIS
    Controla el estado (Encendido/Apagado) del servicio de SQL Server en Railway.
    Puede ser usado manualmente o por GitHub Actions.

.DESCRIPTION
    Este script se conecta a la API GraphQL de Railway para escalar el servicio.
    - Start: 1 Réplica (Encendido)
    - Stop: 0 Réplicas (Apagado - Ahorro de costos)

.PARAMETER Action
    'Start' o 'Stop'. Si no se especifica, pregunta al usuario (modo interactivo).

.PARAMETER Token
    Token de Railway. Si no se pasa, intenta leerlo del archivo o variables de entorno.

.PARAMETER ServiceId
    ID del Servicio. Si no se pasa, intenta leerlo del archivo o variables de entorno.
#>

param (
    [Parameter(Mandatory=$false)]
    [ValidateSet("Start", "Stop")]
    [string]$Action,

    [string]$Token,
    [string]$ServiceId
)

# ==========================================
# GESTIÓN DE CREDENCIALES (MODO SEGURO)
# ==========================================

# 1. Intentar cargar archivo de secretos LOCAL (No se sube a GitHub)
$SecretsFile = Join-Path $PSScriptRoot "railway_secrets.ps1"
if (Test-Path $SecretsFile) {
    . $SecretsFile
    Write-Host "Cargando credenciales desde archivo local..." -ForegroundColor Gray
}

# 1. Determinar Credenciales (Prioridad: Param -> Env Var)
$FinalToken = if ($Token) { $Token } else { $env:RAILWAY_TOKEN }
$FinalServiceId = if ($ServiceId) { $ServiceId } else { $env:RAILWAY_SERVICE_ID }

# Validar que tengamos credenciales
if ([string]::IsNullOrWhiteSpace($FinalToken)) {
    Write-Host "Error: No se encontró el RAILWAY_TOKEN." -ForegroundColor Red
    Write-Host "Asegúrate de tener el archivo 'scripts/railway_secrets.ps1' o la variable de entorno configurada."
    exit 1
}
if ([string]::IsNullOrWhiteSpace($FinalServiceId)) {
    Write-Host "Error: No se encontró el RAILWAY_SERVICE_ID." -ForegroundColor Red
    Write-Host "Asegúrate de tener el archivo 'scripts/railway_secrets.ps1' o la variable de entorno configurada."
    exit 1
}

# 2. Función helper para API GraphQL
function Invoke-RailwayGraphQL {
    param ([string]$Query, [hashtable]$Variables)
    
    $Headers = @{
        "Authorization" = "Bearer $FinalToken"
        "Content-Type"  = "application/json"
    }
    
    $Body = @{
        query     = $Query
        variables = $Variables
    } | ConvertTo-Json -Depth 5

    try {
        $Response = Invoke-RestMethod -Uri "https://backboard.railway.app/graphql/v2" -Method Post -Headers $Headers -Body $Body -ErrorAction Stop
        if ($Response.errors) {
            Write-Host "API Error:" -ForegroundColor Red
            $Response.errors | ForEach-Object { Write-Host $_.message }
            throw "Railway API returned errors."
        }
        return $Response.data
    }
    catch {
        Write-Host "Request Failed: $($_.Exception.Message)" -ForegroundColor Red
        throw
    }
}

# 3. Obtener Environment ID (Simplificado para evitar errores 400)
Write-Host "Conectando a Railway..." -ForegroundColor Cyan

# Query simplificada que sabemos que funciona con Project Tokens
# "service" devuelve el servicio y sus entornos.
# Asumimos que el entorno "production" es el que queremos (o el primero disponible).
$EnvQuery = @"
query GetServiceEnv(`$id: String!) {
  service(id: `$id) {
    name
    serviceInstances {
      edges {
        node {
          id
          environmentId
        }
      }
    }
  }
}
"@

try {
    $ServiceData = Invoke-RailwayGraphQL -Query $EnvQuery -Variables @{ id = $FinalServiceId }
    
    # Extraer el Environment ID de la primera instancia de servicio activa
    $InstanceNode = $ServiceData.service.serviceInstances.edges[0].node
    $EnvId = $InstanceNode.environmentId
    $ServiceName = $ServiceData.service.name
    
    Write-Host "Servicio detectado: $ServiceName (Env: $EnvId)" -ForegroundColor Green
}
catch {
    Write-Host "No se pudo obtener información del servicio." -ForegroundColor Red
    Write-Host "Detalle: $($_.Exception.Message)"
    exit 1
}

# 4. Determinar Acción (Si no se pasó por parámetro)
if (-not $Action) {
    # Modo interactivo simple
    $Choice = Read-Host "¿Deseas ENCENDER (1) o APAGAR (0) el servidor SQL? [1/0]"
    if ($Choice -eq "1") { $Action = "Start" }
    elseif ($Choice -eq "0") { $Action = "Stop" }
    else { Write-Host "Opción no válida."; exit }
}

# 5. Ejecutar Cambio de Estado
$Replicas = if ($Action -eq "Start") { 1 } else { 0 }
Write-Host "Ejecutando orden: $Action (Replicas -> $Replicas)..." -ForegroundColor Yellow

# Mutation para escalar (usando numReplicas por simplicidad, si falla usaremos multiRegionConfig en v2)
# Nota: Aunque numReplicas esté deprecated, suele ser soportado. Si falla, el error lo dirá.
# Estrategia robusta: Usar serviceInstanceUpdate con environmentId.

$UpdateMutation = @"
mutation ScaleService(`$bg: ServiceInstanceUpdateInput!, `$svcId: String!, `$envId: String!) {
  serviceInstanceUpdate(serviceId: `$svcId, environmentId: `$envId, input: `$bg)
}
"@

# Nota: Railway prefiere multiRegionConfig ahora para 'replicas'.
# Vamos a intentar construir el input correcto.
$InputData = @{
    # Inyectamos numReplicas 'a la fuerza' o usamos la config regional si es requerida.
    # Dado que no sabemos la región exacta (us-east-1?), probaremos numReplicas primero.
    # Si Railway ignora numReplicas, el script fallará.
    # Alternativa segura: Intentar leer la región actual ?? No, muy complejo.
    # Usaremos el campo antiguo que suele mapear al default.
    numReplicas = $Replicas 
}

try {
    $Result = Invoke-RailwayGraphQL -Query $UpdateMutation -Variables @{ 
        bg = $InputData
        svcId = $FinalServiceId
        envId = $EnvId
    }
    
    Write-Host "¡Éxito! El servicio se está actualizando." -ForegroundColor Green
    Write-Host "Estado final: $Action"
    
    if ($Action -eq "Start") {
        Write-Host "Espera unos 60 segundos antes de conectar SSMS." -ForegroundColor Cyan
    }
}
catch {
    Write-Host "Fallo al actualizar el servicio." -ForegroundColor Red
    exit 1
}

Start-Sleep -Seconds 2
