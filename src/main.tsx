import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { App } from './App'
import { LangProvider } from './i18n'
import { StoreProvider } from './store'
import { UIProvider } from './ui'
import './styles.css'

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <LangProvider>
      <StoreProvider>
        <UIProvider>
          <App />
        </UIProvider>
      </StoreProvider>
    </LangProvider>
  </StrictMode>,
)
