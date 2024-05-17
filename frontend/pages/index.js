import React, { useEffect, useState } from 'react';
import CustomBarChart from '../components/BarChart';

export default function Home() {
  const [sponsorsData, setSponsorsData] = useState([]);
  const [conditionsData, setConditionsData] = useState([]);

  useEffect(() => {
    const fetchData = async () => {
      const sponsorsResponse = await fetch('/api/sponsors');
      const sponsorsData = await sponsorsResponse.json();
      setSponsorsData(sponsorsData);

      const conditionsResponse = await fetch('/api/conditions');
      const conditionsData = await conditionsResponse.json();
      setConditionsData(conditionsData);
    };
    fetchData();
  }, []);

  return (
    <div>
      <h1>Miracle - Clinical Trials Data</h1>
      <CustomBarChart
        data={sponsorsData}
        xKey="sponsor"
        yKey="trial_count"
        title="Number of Trials by Sponsor"
      />
      <CustomBarChart
        data={conditionsData}
        xKey="conditions"
        yKey="trial_count"
        title="Number of Trials by Condition"
      />
    </div>
  );
}
