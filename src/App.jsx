import React from 'react';
import { AuthProvider, useAuth } from './context/AuthContext';
import { supabase } from './lib/supabase';

function Login() {
  const [email, setEmail] = React.useState('');
  const [password, setPassword] = React.useState('');
  const [loading, setLoading] = React.useState(false);

  const handleLogin = async (e) => {
    e.preventDefault();
    setLoading(true);
    const { error } = await supabase.auth.signInWithPassword({ email, password });
    if (error) alert(error.message);
    setLoading(false);
  };

  return (
    <div style={{ padding: '2rem', maxWidth: '400px', margin: '0 auto' }}>
      <h2>Ingreso - ERP IGSS</h2>
      <form onSubmit={handleLogin} style={{ display: 'flex', flexDirection: 'column', gap: '1rem' }}>
        <input 
          type="email" 
          placeholder="Correo Institucional" 
          value={email} 
          onChange={(e) => setEmail(e.target.value)} 
          style={{ padding: '0.5rem' }} 
        />
        <input 
          type="password" 
          placeholder="Contraseña" 
          value={password} 
          onChange={(e) => setPassword(e.target.value)} 
          style={{ padding: '0.5rem' }} 
        />
        <button type="submit" disabled={loading} style={{ padding: '0.5rem', cursor: 'pointer' }}>
          {loading ? 'Cargando...' : 'Iniciar Sesión'}
        </button>
      </form>
    </div>
  );
}

function Dashboard() {
  const { user, perfil, hasPermiso } = useAuth();

  return (
    <div style={{ padding: '2rem' }}>
      <h1>Dashboard ERP Institucional</h1>
      <p>Bienvenido, {perfil?.nombre_completo || user.email}</p>
      {perfil?.unidades && <p><strong>Unidad:</strong> {perfil.unidades.nombre}</p>}
      
      <div style={{ marginTop: '2rem', display: 'flex', gap: '1rem', flexWrap: 'wrap' }}>
        {hasPermiso('financiero_ver') && (
          <div style={{ border: '1px solid #ccc', padding: '1rem', borderRadius: '8px' }}>
            <h3>?? Módulo Financiero</h3>
            <p>Acceso concedido a presupuestos.</p>
          </div>
        )}
        
        {hasPermiso('pasajes_cajero') && (
          <div style={{ border: '1px solid #ccc', padding: '1rem', borderRadius: '8px' }}>
            <h3>?? Módulo Pasajes (Caja Chica)</h3>
            <p>Acceso concedido a caja chica.</p>
          </div>
        )}
      </div>

      <button onClick={() => supabase.auth.signOut()} style={{ marginTop: '2rem', padding: '0.5rem' }}>
        Cerrar Sesión
      </button>
    </div>
  );
}

function MainApp() {
  const { user, loading } = useAuth();

  if (loading) return <div style={{ padding: '2rem' }}>Cargando sistema...</div>;

  return user ? <Dashboard /> : <Login />;
}

export default function App() {
  return (
    <AuthProvider>
      <MainApp />
    </AuthProvider>
  );
}
