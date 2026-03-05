// Toast notification utility
export interface Toast {
  id: string;
  message: string;
  type: 'success' | 'error' | 'info';
}

let toastListeners: ((toasts: Toast[]) => void)[] = [];
let toasts: Toast[] = [];

export const toast = {
  show: (message: string, type: 'success' | 'error' | 'info' = 'success') => {
    const id = Date.now().toString() + Math.random().toString(36).substr(2, 9);
    const newToast: Toast = { id, message, type };
    toasts = [...toasts, newToast];
    toastListeners.forEach(listener => listener(toasts));
    
    // Auto remove after 3 seconds
    setTimeout(() => {
      toasts = toasts.filter(t => t.id !== id);
      toastListeners.forEach(listener => listener(toasts));
    }, 3000);
  },
  
  subscribe: (listener: (toasts: Toast[]) => void) => {
    toastListeners.push(listener);
    listener(toasts);
    return () => {
      toastListeners = toastListeners.filter(l => l !== listener);
    };
  },
};



