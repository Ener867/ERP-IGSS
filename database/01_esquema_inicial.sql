-- ============================================================================
-- ERP IGSS - ESQUEMA UNIFICADO DE BASE DE DATOS
-- FASE 1: Financiero, Usuarios (Permisos) y Base Institucional
-- ============================================================================

-- 1. TABLA DE UNIDADES (Soporta estructura Madre/Hijo para el Presupuesto)
CREATE TABLE IF NOT EXISTS unidades (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nombre VARCHAR(255) NOT NULL,
    codigo VARCHAR(50) UNIQUE, -- Ej: 12-01-04
    ubicacion VARCHAR(255),
    unidad_madre_id UUID REFERENCES unidades(id) ON DELETE SET NULL, -- Jerarquía de presupuesto
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- 2. TABLA DE USUARIOS (Sistema de Permisos Granulares)
CREATE TABLE IF NOT EXISTS usuarios (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    nombre_completo VARCHAR(255) NOT NULL,
    correo VARCHAR(255) UNIQUE NOT NULL,
    unidad_id UUID REFERENCES unidades(id) ON DELETE SET NULL,
    -- Reemplazamos el 'rol' por un array JSON de permisos: ej. ["financiero_admin", "sps_digitador"]
    permisos JSONB DEFAULT '[]'::jsonb NOT NULL, 
    activo BOOLEAN DEFAULT true NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- ============================================================================
-- MÓDULO FINANCIERO (Presupuestos)
-- ============================================================================

-- 3. PRESUPUESTOS ANUALES (Asignación por Renglón)
CREATE TABLE IF NOT EXISTS presupuestos_anuales (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    unidad_id UUID NOT NULL REFERENCES unidades(id) ON DELETE CASCADE,
    anio INTEGER NOT NULL,
    renglon VARCHAR(20) NOT NULL, -- Ej: '114', '182', etc.
    monto_inicial DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    monto_actual DECIMAL(12,2) NOT NULL DEFAULT 0.00, -- Se actualiza con reprogramaciones y gastos
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    UNIQUE(unidad_id, anio, renglon)
);

-- 4. REPROGRAMACIONES (Movimientos entre renglones o unidades)
CREATE TABLE IF NOT EXISTS reprogramaciones (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    presupuesto_origen_id UUID REFERENCES presupuestos_anuales(id) ON DELETE CASCADE,
    presupuesto_destino_id UUID REFERENCES presupuestos_anuales(id) ON DELETE CASCADE,
    monto DECIMAL(12,2) NOT NULL CHECK (monto > 0),
    motivo TEXT NOT NULL,
    fecha DATE DEFAULT CURRENT_DATE NOT NULL,
    autorizado_por UUID REFERENCES usuarios(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- 5. CAJAS CHICAS (Fondos Rotativos extraídos del Presupuesto para Pasajes/Viáticos)
CREATE TABLE IF NOT EXISTS cajas_chicas (
    id SERIAL PRIMARY KEY,
    unidad_id UUID NOT NULL REFERENCES unidades(id) ON DELETE CASCADE,
    presupuesto_id UUID REFERENCES presupuestos_anuales(id), -- De qué renglón salió el dinero
    codigo_caja VARCHAR(50) NOT NULL,      -- Ej: 1/2026
    monto_inicial DECIMAL(10,2) NOT NULL,   
    monto_disponible DECIMAL(10,2) NOT NULL, 
    estado VARCHAR(50) DEFAULT 'abierta' NOT NULL CHECK (estado IN ('abierta', 'cerrada', 'liquidada')),
    responsable_id UUID REFERENCES usuarios(id),
    fecha_apertura DATE DEFAULT CURRENT_DATE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    UNIQUE(unidad_id, codigo_caja)
);

-- ============================================================================
-- MÓDULO DE PASAJES (Pacientes)
-- ============================================================================

-- 6. PATRONOS
CREATE TABLE IF NOT EXISTS patronos (
    patronal_id VARCHAR(50) PRIMARY KEY,
    nombre_patrono VARCHAR(255) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- 7. AFILIADOS / PACIENTES
CREATE TABLE IF NOT EXISTS afiliados (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    no_afiliacion VARCHAR(50) NOT NULL,
    relacion VARCHAR(10) NOT NULL CHECK (relacion IN ('AF', 'BE', 'BH')),
    nombre_completo VARCHAR(255) NOT NULL,
    sexo CHAR(1) CHECK (sexo IN ('M', 'F')),
    fecha_nacimiento DATE,
    patronal_id VARCHAR(50) REFERENCES patronos(patronal_id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    UNIQUE(no_afiliacion, relacion)
);

-- 8. TARIFAS DE PASAJES POR DESTINO
CREATE TABLE IF NOT EXISTS tarifas_pasajes (
    id SERIAL PRIMARY KEY,
    unidad_id UUID NOT NULL REFERENCES unidades(id) ON DELETE CASCADE,
    destino VARCHAR(255) NOT NULL,
    tarifa_base DECIMAL(10,2) NOT NULL,
    descripcion VARCHAR(255) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    UNIQUE(unidad_id, destino)
);

-- 9. RECIBOS DE PASAJE (Gasto de Caja Chica)
CREATE TABLE IF NOT EXISTS recibos_pasaje (
    id SERIAL PRIMARY KEY,
    comprobante_no INTEGER NOT NULL, 
    caja_chica_id INTEGER NOT NULL REFERENCES cajas_chicas(id) ON DELETE CASCADE,
    afiliado_id UUID NOT NULL REFERENCES afiliados(id),
    tarifa_id INTEGER NOT NULL REFERENCES tarifas_pasajes(id),
    cantidad INTEGER DEFAULT 1 NOT NULL CHECK (cantidad >= 1),
    monto_total DECIMAL(10,2) NOT NULL,
    fechas_viaje JSONB NOT NULL,
    fecha_pago DATE DEFAULT CURRENT_DATE NOT NULL,
    creado_por UUID NOT NULL REFERENCES usuarios(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    UNIQUE(caja_chica_id, comprobante_no)
);

-- ============================================================================
-- TRIGGERS PARA CONTROL DE FONDOS (Automatización)
-- ============================================================================

-- Trigger para descontar automáticamente la caja chica cuando se emite un pasaje
CREATE OR REPLACE FUNCTION fn_descontar_caja_chica()
RETURNS TRIGGER AS $func$
DECLARE
    v_saldo_actual DECIMAL(10,2);
BEGIN
    IF TG_OP = 'INSERT' THEN
        -- Verificar saldo
        SELECT monto_disponible INTO v_saldo_actual FROM cajas_chicas WHERE id = NEW.caja_chica_id;
        IF v_saldo_actual < NEW.monto_total THEN
            RAISE EXCEPTION 'Fondos insuficientes en la Caja Chica. Saldo: %, Intento de cobro: %', v_saldo_actual, NEW.monto_total;
        END IF;
        -- Restar saldo
        UPDATE cajas_chicas SET monto_disponible = monto_disponible - NEW.monto_total WHERE id = NEW.caja_chica_id;
    END IF;
    RETURN NEW;
END;
$func$ LANGUAGE plpgsql;

CREATE TRIGGER trg_recibo_pasaje_insert
AFTER INSERT ON recibos_pasaje
FOR EACH ROW EXECUTE FUNCTION fn_descontar_caja_chica();

-- ============================================================================
-- RLS (ROW LEVEL SECURITY) Básico
-- ============================================================================
ALTER TABLE unidades ENABLE ROW LEVEL SECURITY;
ALTER TABLE usuarios ENABLE ROW LEVEL SECURITY;
ALTER TABLE presupuestos_anuales ENABLE ROW LEVEL SECURITY;
ALTER TABLE reprogramaciones ENABLE ROW LEVEL SECURITY;
ALTER TABLE cajas_chicas ENABLE ROW LEVEL SECURITY;
ALTER TABLE recibos_pasaje ENABLE ROW LEVEL SECURITY;

-- Políticas globales para lectura (todos los usuarios autenticados pueden leer catálogos base)
CREATE POLICY "unidades_select" ON unidades FOR SELECT TO authenticated USING (true);
CREATE POLICY "usuarios_select" ON usuarios FOR SELECT TO authenticated USING (true);

-- (Las políticas de escritura se basarán en jsonb_exists(permisos, 'permiso_xyz'))
