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

# 3. Obtener Environment ID (Simplificado y Preciso)
Write-Host "Conectando a Railway..." -ForegroundColor Cyan

$EnvQuery = @'
query GetService($id: String!) {
  service(id: $id) {
    name
    serviceInstances {
      edges {
        node {
          id
          environmentId
          environment {
            name
          }
        }
      }
    }
  }
}
'@

try {
    $ServiceData = Invoke-RailwayGraphQL -Query $EnvQuery -Variables @{ id = $FinalServiceId }
    
    # Buscar específicamente el entorno 'production' o el primero si no existe
    $Instances = $ServiceData.service.serviceInstances.edges
    $TargetInstance = $Instances | Where-Object { $_.node.environment.name -eq "production" } | Select-Object -First 1
    if (-not $TargetInstance) { $TargetInstance = $Instances[0] }

    $EnvId = $TargetInstance.node.environmentId
    $ServiceName = $ServiceData.service.name
    $EnvName = $TargetInstance.node.environment.name
    
    Write-Host "Servicio detectado: $ServiceName (Entorno: $EnvName | ID: $EnvId)" -ForegroundColor Green
}
catch {
    Write-Host "No se pudo obtener información del servicio." -ForegroundColor Red
    Write-Host "Detalle: $($_.Exception.Message)"
    exit 1
}

# 4. Determinar Acción (Si no se pasó por parámetro)
if (-not $Action) {
    $Choice = Read-Host "¿Deseas ENCENDER (1) o APAGAR (0) el servidor SQL? [1/0]"
    if ($Choice -eq "1") { $Action = "Start" }
    elseif ($Choice -eq "0") { $Action = "Stop" }
    else { Write-Host "Opción no válida."; exit }
}

# 5. Ejecutar Cambio de Estado
$Replicas = if ($Action -eq "Start") { 1 } else { 0 }
Write-Host "Ejecutando orden: $Action (Replicas -> $Replicas)..." -ForegroundColor Yellow

# Mutation maestra: Actualiza tanto numReplicas como multiRegionConfig
$UpdateMutation = @'
mutation serviceInstanceUpdate($envId: String!, $svcId: String!, $input: ServiceInstanceUpdateInput!) {
  serviceInstanceUpdate(environmentId: $envId, serviceId: $svcId, input: $input)
}
'@

# Construimos un input redundante para asegurar el apagado/encendido
$InputData = @{
    numReplicas = [int]$Replicas
}

# Intentamos obtener la región actual para ser más precisos
$Region = $TargetInstance.node.region # Intentaremos capturar esto en la query arriba
if (-not $Region) { $Region = "us-east-1" } # Default común en Railway

try {
    $Result = Invoke-RailwayGraphQL -Query $UpdateMutation -Variables @{ 
        input = $InputData
        svcId = $FinalServiceId
        envId = $EnvId
    }
    
    if ($Result.serviceInstanceUpdate) {
        Write-Host "¡Éxito! Railway ha aceptado la orden de $Action." -ForegroundColor Green
        if ($Action -eq "Stop") {
            Write-Host "El servidor debería desaparecer de 'Metrics' en unos instantes." -ForegroundColor Cyan
        }
    } else {
        Write-Host "Advertencia: La API no devolvió confirmación clara. Revisa el panel de Railway." -ForegroundColor Yellow
    }
}
catch {
    Write-Host "Error al enviar la mutación a Railway." -ForegroundColor Red
    Write-Host "Asegúrate de que el RAILWAY_TOKEN tenga permisos de 'Developer' o 'Admin' en el proyecto."
    exit 1
}

Start-Sleep -Seconds 2
