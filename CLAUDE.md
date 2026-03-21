# Instruções do Projeto BolãoPro

## Estratégia para Arquivos Grandes

Sempre que precisar criar arquivos com mais de ~400 linhas, **nunca gerar tudo em uma única operação**. Dividir em partes:

1. **Parte 1 — Estrutura (HTML/CSS):** usar a ferramenta `Write` com até ~400 linhas
2. **Parte 2 em diante — Conteúdo adicional (JS, etc.):** usar `Bash` com `cat >> arquivo` (heredoc) para fazer append

### Exemplo de padrão:
```bash
# Append de JS após o HTML já escrito:
cat >> /caminho/arquivo.html << 'EOF'
<script>
  // código JS aqui
</script>
</body>
</html>
EOF
```

### Regra geral:
- Nunca tentar gerar 700+ linhas em uma única chamada `Write` ou dentro de um agente
- Preferir 2–4 operações menores e sequenciais
- Usar `wc -l arquivo` ao final para confirmar que o arquivo foi criado corretamente
