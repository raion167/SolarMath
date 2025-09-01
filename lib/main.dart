//import 'dart:ffi';//

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
// 👇 ALTERAÇÃO: import para compartilhar no WhatsApp
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

//FUNÇÃO PARA CALCULAR O PARCELAMENTO E JUROS
Map<String, double> calcularParcelamento(int parcelas, double valor) {
  double taxaJuros = 0.021; // 2,1% AO MÊS
  double fator = (taxaJuros * (pow(1 + taxaJuros, parcelas))) /
      (pow(1 + taxaJuros, parcelas) - 1);
  double valorParcela = valor * fator;
  double totalPago = valorParcela * parcelas;
  double jurosTotal = totalPago - valor;

  return {
    "parcela": valorParcela,
    "total": totalPago,
    "juros": jurosTotal,
  };
}

void main() {
  runApp(SolarApp());
}

class SolarApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AlphaMath - Simulador de Orçamentos',
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

  //MAPA DE ARRAYS PARA CALCULAR O INVERSOR E SUA CAPACIDADE MAXIMA
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
  //=======================================================================

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

    // ========= CALCULO DA QUANTIDADE E CAPACIDADE DE INVERSORES
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
                  backgroundColor: const Color.fromARGB(255, 6, 133, 72),
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
                child: const Text("Gerar Proposta",
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(8),
        color: Colors.grey.shade900,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Text(
              "Desenvolvido por João Pedro",
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            Text(
              "© 2025 - Todos os direitos reservados",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

//CAIXA DE TEXTO DE INVESTIMENTO E GERAÇÃO
class InfoCard extends StatelessWidget {
  final String titulo;
  final String valor;
  final Color corValor;
  final List<Color> gradientColors;

  const InfoCard({
    Key? key,
    required this.titulo,
    required this.valor,
    required this.corValor,
    required this.gradientColors,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.6),
            blurRadius: 8,
            offset: const Offset(2, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            titulo,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            valor,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          )
        ],
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
    //MONTANDO O TEXTO DE PARCELAS
    final parcelasT = [36, 48, 60, 72, 84];
    final propostasT = parcelasT
        .map((p) => {"p": p, "dados": calcularParcelamento(p, investimento)})
        .toList();

    String parcelasTexto = propostasT.map((p) {
      final dados = p["dados"] as Map<String, double>;
      return "${p["p"]}x de ${moeda.format(dados["parcela"])}";
    }).join("\n");

    // Texto do orçamento (para PDF e copiar)
    String orcamentoTexto = """
    DESCRIÇÃO DO KIT
    Cliente: $nome
    Sistema Fotovoltaico de ${potenciaTotal.toStringAsFixed(2)} kWp 
    com $qtdPaineis Painéis (585W) + $qtdInversores Inversor $potenciaInversor

    Valor do Investimento: ${moeda.format(investimento)}

    ESTIMATIVA DE PARCELA (3 meses de carência)
  $parcelasTexto

    Geração Mensal: ${geracaoMensal.toStringAsFixed(2)} kWh
    Economia Mensal: ${moeda.format(economiaMensal)}
    Potência do Sistema: ${potenciaTotal.toStringAsFixed(2)} kWp

    Economia Anual: ${moeda.format(economiaAnual)}
    Economia em 25 anos: ${moeda.format(economia25anos)}
    """;

    // LOGICA DE PARCELAMENTOS E JUROS
    final parcelas = [36, 48, 60, 72, 84];
    final propostas = parcelas
        .map((p) => {"p": p, "dados": calcularParcelamento(p, investimento)})
        .toList();

    return Scaffold(
      appBar: AppBar(title: Text("AlphaMath - Simulador de Orçamentos")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 800),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // ✅ Agora usa InfoCard
                Row(
                  children: [
                    Expanded(
                      child: InfoCard(
                        titulo: "Valor do Investimento",
                        valor: moeda.format(investimento),
                        corValor: Colors.white,
                        gradientColors: [
                          Colors.green.shade900,
                          Colors.green.shade600
                        ],
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: InfoCard(
                        titulo: "Geração Mensal",
                        valor: "${geracaoMensal.toStringAsFixed(2)} kWh",
                        corValor: Colors.black,
                        gradientColors: [
                          Colors.amber.shade900,
                          Colors.amber.shade600
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 24),
                // Texto centralizado
                Text(
                  orcamentoTexto,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),

                SizedBox(height: 24),
                // Botões centralizados
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.center,
                  children: [
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
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.greenAccent,
                        foregroundColor: Colors.black,
                      ),
                      //=== EXPORTAÇÃO E FORMATAÇÃO DO PDF ========//
                      onPressed: () async {
                        final pdf = pw.Document();
                        pdf.addPage(
                          pw.Page(
                            pageFormat: PdfPageFormat.a4,
                            build: (pw.Context context) {
                              return pw.Column(
                                crossAxisAlignment:
                                    pw.CrossAxisAlignment.center,
                                children: [
                                  // Cabeçalho centralizado
                                  pw.Center(
                                    child: pw.Column(
                                      children: [
                                        pw.SizedBox(height: 8),
                                        pw.Text(
                                          "ALPHA ENERGIA",
                                          style: pw.TextStyle(
                                              fontSize: 18,
                                              fontWeight: pw.FontWeight.bold),
                                          textAlign: pw.TextAlign.center,
                                        ),
                                        pw.Text(
                                          "PROPOSTA COMERCIAL",
                                          style: pw.TextStyle(fontSize: 12),
                                          textAlign: pw.TextAlign.center,
                                        ),
                                      ],
                                    ),
                                  ),
                                  pw.SizedBox(height: 20),

                                  // Corpo do orçamento: duas colunas
                                  pw.Row(
                                    crossAxisAlignment:
                                        pw.CrossAxisAlignment.start,
                                    mainAxisAlignment:
                                        pw.MainAxisAlignment.spaceBetween,
                                    children: [
                                      // Coluna esquerda
                                      pw.Expanded(
                                        child: pw.Column(
                                          crossAxisAlignment:
                                              pw.CrossAxisAlignment.start,
                                          children: [
                                            // Data
                                            pw.Text(
                                              "Data: ${DateTime.now().day.toString().padLeft(2, '0')}/${DateTime.now().month.toString().padLeft(2, '0')}/${DateTime.now().year}",
                                              style: pw.TextStyle(fontSize: 12),
                                            ),
                                            pw.SizedBox(height: 12),

                                            // DADOS DO CLIENTE
                                            pw.Container(
                                              padding: pw.EdgeInsets.all(8),
                                              color: PdfColors.grey200,
                                              child: pw.Column(
                                                crossAxisAlignment:
                                                    pw.CrossAxisAlignment.start,
                                                children: [
                                                  pw.Text(
                                                    "DADOS DO CLIENTE",
                                                    style: pw.TextStyle(
                                                        fontSize: 14,
                                                        fontWeight:
                                                            pw.FontWeight.bold),
                                                  ),
                                                  pw.SizedBox(height: 4),
                                                  pw.Text("Cliente: $nome",
                                                      style: pw.TextStyle(
                                                          fontSize: 12)),
                                                  pw.Text(
                                                      "Consumo Mensal: ${consumo.toStringAsFixed(2)} kWh",
                                                      style: pw.TextStyle(
                                                          fontSize: 12)),
                                                ],
                                              ),
                                            ),
                                            pw.SizedBox(height: 12),

                                            // INVESTIMENTO E ECONOMIA
                                            pw.Container(
                                              padding: pw.EdgeInsets.all(8),
                                              color: PdfColors.green100,
                                              child: pw.Column(
                                                crossAxisAlignment:
                                                    pw.CrossAxisAlignment.start,
                                                children: [
                                                  pw.Text(
                                                    "INVESTIMENTO E ECONOMIA",
                                                    style: pw.TextStyle(
                                                        fontSize: 14,
                                                        fontWeight:
                                                            pw.FontWeight.bold),
                                                  ),
                                                  pw.SizedBox(height: 4),
                                                  pw.Text(
                                                      "Valor do Investimento: ${moeda.format(investimento)}",
                                                      style: pw.TextStyle(
                                                          fontSize: 12)),
                                                  pw.Text(
                                                      "Geração Mensal: ${geracaoMensal.toStringAsFixed(2)} kWh",
                                                      style: pw.TextStyle(
                                                          fontSize: 12)),
                                                  pw.Text(
                                                      "Economia Anual: ${moeda.format(economiaAnual)}",
                                                      style: pw.TextStyle(
                                                          fontSize: 12)),
                                                ],
                                              ),
                                            ),
                                            pw.SizedBox(height: 12),

                                            // OPÇÕES DE PARCELAMENTO
                                            pw.Container(
                                              padding: pw.EdgeInsets.all(8),
                                              color: PdfColors.blue100,
                                              child: pw.Column(
                                                crossAxisAlignment:
                                                    pw.CrossAxisAlignment.start,
                                                children: [
                                                  pw.Text(
                                                    "OPÇÕES DE PARCELAMENTO",
                                                    style: pw.TextStyle(
                                                        fontSize: 14,
                                                        fontWeight:
                                                            pw.FontWeight.bold),
                                                  ),
                                                  pw.SizedBox(height: 4),
                                                  pw.Text(
                                                    "$parcelasTexto",
                                                    style: pw.TextStyle(
                                                        fontSize: 12),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),

                                      pw.SizedBox(width: 10),

                                      // Coluna direita
                                      pw.Expanded(
                                        child: pw.Column(
                                          crossAxisAlignment:
                                              pw.CrossAxisAlignment.start,
                                          children: [
                                            // SISTEMA PROPOSTO
                                            pw.Container(
                                              padding: pw.EdgeInsets.all(8),
                                              color: PdfColors.yellow100,
                                              child: pw.Column(
                                                crossAxisAlignment:
                                                    pw.CrossAxisAlignment.start,
                                                children: [
                                                  pw.Text(
                                                    "SISTEMA PROPOSTO",
                                                    style: pw.TextStyle(
                                                        fontSize: 14,
                                                        fontWeight:
                                                            pw.FontWeight.bold),
                                                  ),
                                                  pw.SizedBox(height: 4),
                                                  pw.Text(
                                                      "Potência do Kit: ${potenciaTotal.toStringAsFixed(2)} kWp",
                                                      style: pw.TextStyle(
                                                          fontSize: 12)),
                                                  pw.Text(
                                                      "Quantidade de Paineis: $qtdPaineis",
                                                      style: pw.TextStyle(
                                                          fontSize: 12)),
                                                  pw.Text(
                                                      "Inversor: $qtdInversores de $potenciaInversor",
                                                      style: pw.TextStyle(
                                                          fontSize: 12)),
                                                ],
                                              ),
                                            ),
                                            pw.SizedBox(height: 12),

                                            // PREÇO POR KWH E ECONOMIAS
                                            pw.Container(
                                              padding: pw.EdgeInsets.all(8),
                                              color: PdfColors.orange100,
                                              child: pw.Column(
                                                crossAxisAlignment:
                                                    pw.CrossAxisAlignment.start,
                                                children: [
                                                  pw.SizedBox(height: 4),
                                                  pw.Text(
                                                      "Preço por kWh: ${moeda.format(precoPorKwp)}",
                                                      style: pw.TextStyle(
                                                          fontSize: 12)),
                                                  pw.Text(
                                                      "Economia Mensal: ${moeda.format(economiaMensal)}",
                                                      style: pw.TextStyle(
                                                          fontSize: 12)),
                                                  pw.Text(
                                                      "Economia em 25 anos: ${moeda.format(economia25anos)}",
                                                      style: pw.TextStyle(
                                                          fontSize: 12)),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),

                                  pw.SizedBox(height: 20),
                                  pw.Divider(),

                                  // RESUMO TÉCNICO
                                  pw.Container(
                                    padding: pw.EdgeInsets.all(8),
                                    color: PdfColors.grey300,
                                    child: pw.Column(
                                      crossAxisAlignment:
                                          pw.CrossAxisAlignment.start,
                                      children: [
                                        pw.Text(
                                          "RESUMO TÉCNICO",
                                          style: pw.TextStyle(
                                              fontSize: 12,
                                              fontWeight: pw.FontWeight.bold),
                                        ),
                                        pw.SizedBox(height: 4),
                                        pw.Bullet(
                                            text:
                                                "Sistema Fotovoltaico de ${potenciaTotal.toStringAsFixed(2)} kWp"),
                                        pw.Bullet(
                                            text:
                                                "$qtdPaineis Painéis Solares de 585 W cada"),
                                        pw.Bullet(
                                            text:
                                                "$qtdInversores inversor de $potenciaInversor para conversão CC/CA"),
                                        pw.Bullet(
                                            text:
                                                "Estimativa de geração: ${geracaoMensal.toStringAsFixed(2)} kWh/mês"),
                                        pw.Bullet(
                                            text:
                                                "Economia estimada: ${moeda.format(economiaMensal)}/mês"),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        );
                        await Printing.layoutPdf(
                            onLayout: (PdfPageFormat format) async =>
                                pdf.save());
                      },
                      child: Text("Exportar em PDF"),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () async {
                        final url = Uri.parse(
                            "https://wa.me/?text=${Uri.encodeComponent(orcamentoTexto)}");
                        if (await canLaunchUrl(url)) {
                          await launchUrl(url,
                              mode: LaunchMode.externalApplication);
                        }
                      },
                      label: Text("Compartilhar"),
                    ),
                  ],
                ),

                SizedBox(height: 32),
                Text("Propostas de Parcelamento",
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),

                SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    // se largura < 600px, scroll horizontal
                    if (constraints.maxWidth < 600) {
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: propostas.map((p) {
                            final dados = p["dados"] as Map<String, double>;
                            return _buildCaixaParcelamento(p, dados, moeda);
                          }).toList(),
                        ),
                      );
                    } else {
                      // em telas grandes -> centralizado em grid
                      return Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 16,
                        runSpacing: 16,
                        children: propostas.map((p) {
                          final dados = p["dados"] as Map<String, double>;
                          return _buildCaixaParcelamento(p, dados, moeda);
                        }).toList(),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCaixaParcelamento(
      Map p, Map<String, double> dados, NumberFormat moeda) {
    return Container(
      width: 180,
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.greenAccent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text("${p["p"]}x",
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black)),
          SizedBox(height: 8),
          Text("Parcela: ${moeda.format(dados["parcela"])}",
              style:
                  TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          Text("Total: ${moeda.format(dados["total"])}",
              style:
                  TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          Text("Juros: ${moeda.format(dados["juros"])}",
              style:
                  TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
