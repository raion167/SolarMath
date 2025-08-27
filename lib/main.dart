//import 'dart:ffi';//

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
// 👇 ALTERAÇÃO: import para compartilhar no WhatsApp
import 'package:url_launcher/url_launcher.dart';

void main() {
  runApp(SolarApp());
}

class SolarApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Orçamento Solar',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        primaryColor: Colors.greenAccent,
        textTheme: const TextTheme(
          bodyMedium: TextStyle(color: Colors.white),
        ),
      ),
      home: DadosClientePage(),
    );
  }
}

class DadosClientePage extends StatefulWidget {
  @override
  _DadosClientePageState createState() => _DadosClientePageState();
}

class _DadosClientePageState extends State<DadosClientePage> {
  final _formKey = GlobalKey<FormState>();

  // Controllers dos campos
  final TextEditingController nomeController = TextEditingController();
  final TextEditingController consumoController = TextEditingController();
  final TextEditingController qtdPaineisController = TextEditingController();
  final TextEditingController potenciaTotalController = TextEditingController();

  // Variáveis de estado
  double? precoPorKwp; // preço selecionado pelo usuário
  double? investimento; // investimento calculado (preview)
  double? geracaoMensal; // geração calculada (preview)
  double? economiaMensal;
  double? economiaAnual;
  double? economia25anos;
  double tarifa = 1.05; //Tarifa em R$/KWH

  // ====== CONSTANTES DAS FÓRMULAS ======
  // Potência de um painel (kWp) e geração mensal por painel (kWh/mês)
  static const double _potenciaPainel = 0.585;
  static const double _geracaoPorPainel = 66.1;

  // Converte texto do campo em double aceitando vírgula ou ponto
  double _parseConsumo(String text) {
    return double.tryParse(text.replaceAll(',', '.')) ?? 0;
  }

  // ====== CÁLCULOS EM TEMPO REAL PARA PREVIEW ======
  // Atualiza a UI quando o usuário digita consumo ou muda o preço por kWp
  void calcularCampos(double consumo) {
    // Quantidade de painéis = consumo / geração por painel
    // Arredondamos para BAIXO para não superestimar a geração.
    int qtdPaineis = (consumo / _geracaoPorPainel).floor();
    if (qtdPaineis < 1) qtdPaineis = 1; // garantia de pelo menos 1 painel

    // Potência total = qtd painéis * potência por painel
    double potenciaTotal = qtdPaineis * _potenciaPainel;

    // Geração mensal = qtd painéis * geração por painel
    double geracao = qtdPaineis * _geracaoPorPainel;

    // Investimento = potência total * preço por kWp (se definido)
    double valorInvestimento = 0;
    if (precoPorKwp != null) {
      valorInvestimento = potenciaTotal * precoPorKwp!;
    }

    //=======CALCULO DAS ECONOMIAS=========//
    double economiaMensal = geracao * tarifa;
    double economiaAnual = economiaMensal * 12;
    double economia25anos = economiaAnual * 25;

    // Atualiza campos de exibição
    setState(() {
      qtdPaineisController.text = qtdPaineis.toString();
      potenciaTotalController.text = potenciaTotal.toStringAsFixed(2);
      geracaoMensal = geracao;
      investimento = valorInvestimento;
      economiaMensal = economiaMensal;
      economiaAnual = economiaAnual;
      economia25anos = economia25anos;
    });
  }

  final List<Map<String, dynamic>> tabelaInversores = [
    {"min": 2, "max": 8, "potencia": "3K"},
    {"min": 10, "max": 11, "potencia": "4K"},
    {"min": 12, "max": 13, "potencia": "5K"},
    {"min": 14, "max": 15, "potencia": "6K"},
    {"min": 16, "max": 19, "potencia": "7,5K"},
    {"min": 20, "max": 20, "potencia": "8K"},
    {"min": 21, "max": 26, "potencia": "10K"},
    {"min": 27, "max": 36, "potencia": "15K"},
    {"min": 38, "max": 51, "potencia": "20K"},
    {"min": 52, "max": 76, "potencia": "30K"},
    {"min": 77, "max": 92, "potencia": "36K"},
    {"min": 93, "max": 107, "potencia": "37,5K"},
    {"min": 108, "max": 145, "potencia": "50K"},
  ];

  Map<String, dynamic> calcularInversor(int qtdPaineis) {
    for (var faixa in tabelaInversores) {
      if (qtdPaineis >= faixa["min"] && qtdPaineis <= faixa["max"]) {
        return {
          "qtd": 1,
          "potencia": faixa["potencia"],
        };
      }
    }
    return {
      "qtd": 1,
      "potencia": "Não definido",
    };
  }

  // ====== GERAÇÃO DO ORÇAMENTO (RECALCULA PARA GARANTIR CONSISTÊNCIA) ======
  void _gerarOrcamento() {
    final consumo = _parseConsumo(consumoController.text);

    // Recalcula tudo aqui para evitar valores defasados:
    int qtdPaineis = (consumo / _geracaoPorPainel).floor();
    if (qtdPaineis < 1) qtdPaineis = 1;

    double potenciaTotal = qtdPaineis * _potenciaPainel;
    double geracao = qtdPaineis * _geracaoPorPainel;

    final preco = precoPorKwp ?? 0;
    double valorInvestimento = potenciaTotal * preco;
    // ========== CALCULO DAS ECONOMIAS ========
    double economiaMensal = geracao * tarifa;
    double economiaAnual = economiaMensal * 12;
    double economia25anos = economiaAnual * 25;

    final inv = calcularInversor(qtdPaineis);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OrcamentoPage(
          nome: nomeController.text,
          consumo: consumo,
          qtdPaineis: qtdPaineis,
          potenciaTotal: potenciaTotal,
          precoPorKwp: preco,
          investimento: valorInvestimento,
          geracaoMensal: geracao,
          economiaMensal: economiaMensal,
          economiaAnual: economiaAnual,
          economia25anos: economia25anos,
          qtdInversores: inv["qtd"],
          potenciaInversor: inv["potencia"],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("AlphaMath - Simulador de Orçamentos")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              // Nome
              TextFormField(
                controller: nomeController,
                decoration: const InputDecoration(
                  labelText: "Nome do Cliente",
                  labelStyle: TextStyle(color: Colors.greenAccent),
                ),
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 16),

              // Consumo (aceita inteiro/decimal e vírgula/ponto)
              TextFormField(
                controller: consumoController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                      RegExp(r'[\d,.]')), // permite 0-9 , .
                ],
                decoration: const InputDecoration(
                  labelText: "Consumo Mensal (kWh)",
                  labelStyle: TextStyle(color: Colors.greenAccent),
                ),
                style: const TextStyle(color: Colors.white),
                onChanged: (value) {
                  final consumo = _parseConsumo(value);
                  calcularCampos(consumo);
                },
              ),
              const SizedBox(height: 16),

              // Quantidade de painéis (somente leitura)
              TextFormField(
                controller: qtdPaineisController,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: "Quantidade de Painéis",
                  labelStyle: TextStyle(color: Colors.greenAccent),
                ),
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 16),

              // Potência total (somente leitura)
              TextFormField(
                controller: potenciaTotalController,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: "Potência Total (kWp)",
                  labelStyle: TextStyle(color: Colors.greenAccent),
                ),
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 16),

              // Preço por kWp (dropdown)
              DropdownButtonFormField<double>(
                value: precoPorKwp,
                dropdownColor: Colors.black,
                decoration: const InputDecoration(
                  labelText: "Preço por kWp",
                  labelStyle: TextStyle(color: Colors.greenAccent),
                ),
                items: List.generate(
                  15,
                  (index) {
                    final value = 2600 + (index * 100);
                    return DropdownMenuItem(
                      value: value.toDouble(),
                      child: Text(
                        "R\$ ${value.toStringAsFixed(2)}",
                        style: const TextStyle(color: Colors.white),
                      ),
                    );
                  },
                ),
                onChanged: (value) {
                  setState(() {
                    precoPorKwp = value;
                  });
                  // Recalcula preview ao mudar o preço
                  final consumo = _parseConsumo(consumoController.text);
                  calcularCampos(consumo);
                },
              ),
              const SizedBox(height: 24),

              // Botão Gerar Orçamento
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.greenAccent,
                  foregroundColor: Colors.black,
                ),
                onPressed: () {
                  // Validação simples: exige consumo > 0 e preço selecionado
                  final consumo = _parseConsumo(consumoController.text);
                  if (consumo <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text("Informe um consumo válido.")),
                    );
                    return;
                  }
                  if (precoPorKwp == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text("Selecione o preço por kWp.")),
                    );
                    return;
                  }
                  _gerarOrcamento();
                },
                child: const Text("GERAR ORÇAMENTO"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

//============RESUMO DO ORÇAMENTO E PAINEIS DE APRESENTAÇÃO
class OrcamentoPage extends StatelessWidget {
  final String nome;
  final double consumo;
  final int qtdPaineis;
  final double potenciaTotal;
  final double precoPorKwp;
  final double investimento;
  final double geracaoMensal;
  final double economiaMensal;
  final double economiaAnual;
  final double economia25anos;
  final int qtdInversores;
  final String potenciaInversor;

  OrcamentoPage({
    required this.nome,
    required this.consumo,
    required this.qtdPaineis,
    required this.potenciaTotal,
    required this.precoPorKwp,
    required this.investimento,
    required this.geracaoMensal,
    required this.economiaMensal,
    required this.economiaAnual,
    required this.economia25anos,
    required this.qtdInversores,
    required this.potenciaInversor,
  });

  @override
  Widget build(BuildContext context) {
    // Formatador de moeda (R$)
    final NumberFormat moeda = NumberFormat.currency(
      locale: 'pt_BR',
      symbol: 'R\$',
    );

    // Texto do orçamento (para PDF e copiar)
    String orcamentoTexto = """
    DESCRIÇÃO DO KIT
    Cliente: $nome
    Sistema Fotovoltaico de ${potenciaTotal.toStringAsFixed(2)} kWp 
    com $qtdPaineis Painéis (585W) + $qtdInversores Inversor $potenciaInversor

    Valor do Investimento: ${moeda.format(investimento)}

    Geração Mensal: ${geracaoMensal.toStringAsFixed(2)} kWh
    Economia Mensal: ${moeda.format(economiaMensal)}
    Potência do Sistema: ${potenciaTotal.toStringAsFixed(2)} kWp

    Economia Anual: ${moeda.format(economiaAnual)}
    Economia em 25 anos: ${moeda.format(economia25anos)}
    """;

    return Scaffold(
      appBar: AppBar(title: Text("AlphaMath - Simulador de Orçamentos")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Caixas lado a lado (Investimento e Geração Mensal)
            Row(
              children: [
                // Caixa Verde (Investimento)
                Expanded(
                  child: Container(
                    padding: EdgeInsets.all(16),
                    margin: EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: Colors.greenAccent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Text(
                          "INVESTIMENTO",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          moeda.format(investimento), // Formatado como moeda
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Caixa Amarela (Geração Mensal)
                Expanded(
                  child: Container(
                    padding: EdgeInsets.all(16),
                    margin: EdgeInsets.only(left: 8),
                    decoration: BoxDecoration(
                      color: Colors.amberAccent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Text(
                          "GERAÇÃO MENSAL",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          "${geracaoMensal.toStringAsFixed(2)} kWh", // 2 casas decimais
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            SizedBox(height: 24),
            // Texto completo do orçamento
            Text(
              orcamentoTexto,
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),

            SizedBox(height: 24),
            // Botão para copiar orçamento
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.greenAccent,
                foregroundColor: Colors.black,
              ),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: orcamentoTexto));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Orçamento copiado!")),
                );
              },
              child: Text("Copiar Orçamento"),
            ),

            SizedBox(height: 12),
            // Botão para exportar em PDF
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.greenAccent,
                foregroundColor: Colors.black,
              ),
              onPressed: () async {
                final pdf = pw.Document();
                pdf.addPage(
                  pw.Page(
                    build: (pw.Context context) {
                      return pw.Text(orcamentoTexto);
                    },
                  ),
                );
                await Printing.layoutPdf(
                    onLayout: (PdfPageFormat format) async => pdf.save());
              },
              child: Text("Exportar em PDF"),
            ),

            SizedBox(height: 12),
            // 👇 ALTERAÇÃO: Botão de compartilhar no WhatsApp
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                final url = Uri.parse(
                    "https://wa.me/?text=${Uri.encodeComponent(orcamentoTexto)}");
                if (await canLaunchUrl(url)) {
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                }
              },
              label: Text("Compartilhar no WhatsApp"),
            ),
          ],
        ),
      ),
    );
  }
}
