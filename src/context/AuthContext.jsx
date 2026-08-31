import React, { createContext, useContext, useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';

const AuthContext = createContext();

export function AuthProvider({ children }) {
  const [user, setUser] = useState(null);
  const [perfil, setPerfil] = useState(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    // Revisar sesión activa
    supabase.auth.getSession().then(({ data: { session } }) => {
      setUser(session?.user ?? null);
      if (session?.user) {
        cargarPerfil(session.user.id);
      } else {
        setLoading(false);
      }
    });

    // Escuchar cambios de autenticación
    const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, session) => {
      setUser(session?.user ?? null);
      if (session?.user) {
        cargarPerfil(session.user.id);
      } else {
        setPerfil(null);
        setLoading(false);
      }
    });

    return () => subscription.unsubscribe();
  }, []);

  const cargarPerfil = async (userId) => {
    const { data, error } = await supabase
      .from('usuarios')
      .select('*, unidades(nombre, unidad_madre_id)')
      .eq('id', userId)
      .single();
    
    if (!error && data) {
      setPerfil(data);
    }
    setLoading(false);
  };

  const hasPermiso = (permiso) => {
    if (!perfil || !perfil.permisos) return false;
    return perfil.permisos.includes(permiso) || perfil.permisos.includes('superadmin');
  };

  return (
    <AuthContext.Provider value={{ user, perfil, loading, hasPermiso }}>
      {children}
    </AuthContext.Provider>
  );
}

export const useAuth = () => useContext(AuthContext);
