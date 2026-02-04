import { LightningElement, wire } from 'lwc';
import getLeadTimeSummary from '@salesforce/apex/LeadStatusTimeController.getLeadTimeSummary';
import { loadScript } from 'lightning/platformResourceLoader';
import ChartJS from '@salesforce/resourceUrl/ChartJS';

export default class LeadStatusChart extends LightningElement {
    chart;
    scriptLoaded = false;
    dataLoaded = false;
    timeSummary;

    @wire(getLeadTimeSummary)
    wiredSummary({ error, data }) {
        if (data) {
            this.timeSummary = data;
            this.dataLoaded = true;
            this.tryRenderChart();
        } else if (error) {
            console.error(error);
        }
    }

    renderedCallback() {
        if (this.scriptLoaded) return;

        loadScript(this, ChartJS)
            .then(() => {
                this.scriptLoaded = true;
                this.tryRenderChart();
            })
            .catch(err => console.error('ChartJS load error', err));
    }

    tryRenderChart() {
        if (this.scriptLoaded && this.dataLoaded) {
            this.initializeChart();
        }
    }

    initializeChart() {
        const canvas = this.template.querySelector('[data-id="chartCanvas"]');
        const ctx = canvas.getContext('2d');

        const labels = this.timeSummary.map(i => i.stage);
        const data = this.timeSummary.map(i => i.minutes);
        const shortLabels = this.timeSummary.map(i => i.shortLabel);

        if (this.chart) this.chart.destroy();

     const topLabelPlugin = {
    id: 'topValueLabels',
    afterDatasetsDraw(chart, args, options) {
        const { ctx } = chart;
        ctx.save();
        ctx.font = 'bold 13px sans-serif';
        ctx.fillStyle = '#000';

        const dataset = chart.getDatasetMeta(0);

        dataset.data.forEach((bar, index) => {
            const text = shortLabels[index];
            const textWidth = ctx.measureText(text).width;

            // ---------------------------
            // ⭐ DYNAMIC SPACING LOGIC ⭐
            // ---------------------------

            // Distance to the top of the chart area
            const chartTop = chart.chartArea.top;

            // Default distance above bar
            let y = bar.y - 12;

            // If bar is very tall → text closer to top → push further up
            if (bar.y - 20 < chartTop + 5) {
                y = chartTop + 10;
            }

            // If bar is very small (short bar) → avoid touching bar
            if (bar.y > chart.chartArea.bottom - 40) {
                y = bar.y - 18;
            }

            // Final safety padding
            if (y < chartTop + 5) {
                y = chartTop + 5;
            }

            const x = bar.x - (textWidth / 2);

            ctx.fillText(text, x, y);
        });

        ctx.restore();
    }
};

        // ⭐ CHART CREATION ⭐
        this.chart = new Chart(ctx, {
            type: 'bar',
            data: {
                labels,
                datasets: [
                    {
                        data,
                        backgroundColor: '#3B82F6',
                        borderRadius: 10
                    }
                ]
            },
            options: {
                plugins: {
                    legend: { display: false },

                    // ⭐ MODERN DARK TOOLTIP ⭐
                    tooltip: {
                        backgroundColor: 'rgba(0, 0, 0, 0.85)',
                        titleFont: { size: 0 },
                        titleColor: 'rgba(0,0,0,0)',
                        displayColors: false,
                        padding: 12,
                        bodyFont: { size: 14, weight: 'bold' },
                        bodyColor: '#FFFFFF',
                        cornerRadius: 8,

                        callbacks: {
                            title: () => '',
                            label: ctx => shortLabels[ctx.dataIndex]
                        }
                    }
                },
                scales: {
                    y: {
                        beginAtZero: true,
                        ticks: { color: '#555', font: { size: 12 } }
                    },
                    x: {
                        ticks: { color: '#444', font: { size: 12 } }
                    }
                }
            },

            plugins: [topLabelPlugin]
        });
    }
}